"""Fake `sounddevice` module, shadowing the real one via PYTHONPATH.

Instead of opening a microphone, `InputStream` connects to a TCP server run by
the test harness and hands whatever audio it receives to the engine's callback
in `blocksize`-sample chunks — exactly as PortAudio would.

Handshake: on connect the harness sends one directive byte.
    0x00  proceed normally
    0x01  raise PortAudioError instead of starting (simulates a device that
          cannot be opened)

The directive is per-connection rather than an env var so a test can make the
first N opens fail and a later retry succeed, which is what the engine's
recovery loop is built around.
"""

import os
import socket
import struct
import threading

import numpy as np

__all__ = ["InputStream", "PortAudioError"]


class PortAudioError(Exception):
    """Mirrors sounddevice.PortAudioError."""


def _recv_exact(sock, count):
    buf = bytearray()
    while len(buf) < count:
        part = sock.recv(count - len(buf))
        if not part:
            raise ConnectionError("test audio channel closed")
        buf.extend(part)
    return bytes(buf)


class InputStream:
    def __init__(self, samplerate=None, channels=1, dtype="float32",
                 blocksize=1024, callback=None, **_kwargs):
        self.samplerate = samplerate
        self.channels = channels
        self.dtype = dtype
        self.blocksize = blocksize
        self.callback = callback
        self._sock = None
        self._thread = None
        self._stop = threading.Event()

    def __enter__(self):
        endpoint = os.environ["OVERHEAR_TEST_AUDIO"]
        host, port = endpoint.rsplit(":", 1)
        self._sock = socket.create_connection((host, int(port)))

        directive = _recv_exact(self._sock, 1)[0]
        if directive:
            self._sock.close()
            self._sock = None
            raise PortAudioError("Error opening InputStream: Device unavailable")

        self._stop.clear()
        self._thread = threading.Thread(target=self._pump, daemon=True)
        self._thread.start()
        return self

    def __exit__(self, *_args):
        self.close()
        return False

    def close(self, ignore_errors=True):
        self._stop.set()
        if self._sock is not None:
            try:
                self._sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self._sock.close()
            self._sock = None

    def stop(self, ignore_errors=True):
        self._stop.set()

    def _pump(self):
        """Deliver received audio to the callback in blocksize-sized chunks."""
        pending = np.empty(0, dtype=np.float32)
        while not self._stop.is_set():
            try:
                header = _recv_exact(self._sock, 4)
                (length,) = struct.unpack("!I", header)
                payload = _recv_exact(self._sock, length)
            except (ConnectionError, OSError, ValueError):
                return

            arrived = np.frombuffer(payload, dtype=np.float32)
            pending = np.concatenate([pending, arrived])

            while len(pending) >= self.blocksize:
                chunk = pending[:self.blocksize]
                pending = pending[self.blocksize:]
                # PortAudio hands over a (frames, channels) buffer.
                self.callback(chunk.reshape(-1, 1), self.blocksize, None, None)
