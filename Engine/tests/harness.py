"""Test harness for Engine/dictation_engine.py.

Runs the engine as a real subprocess — the JSON-line framing over stdout is part
of what these tests cover — with `sounddevice` (and, in the stubbed lane, the two
ML libraries) shadowed by fakes on PYTHONPATH. The engine source is untouched and
has no idea it is under test.
"""

import json
import os
import queue
import socket
import struct
import subprocess
import sys
import threading
import time

import numpy as np

from .constants import CANCEL_MARKER, CHUNK_SAMPLES, SAMPLE_RATE

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
ENGINE_DIR = os.path.dirname(TESTS_DIR)
REPO_ROOT = os.path.dirname(ENGINE_DIR)
ENGINE_PATH = os.path.join(ENGINE_DIR, "dictation_engine.py")

# Run the engine under the same interpreter running the tests. Locally that is
# the project venv (pytest is invoked as .venv/bin/python -m pytest); on CI it is
# whatever python the workflow installed the dependencies into.
ENGINE_PYTHON = os.environ.get("OVERHEAR_TEST_PYTHON", sys.executable)
FAKE_AUDIO_DIR = os.path.join(TESTS_DIR, "fakes", "audio")
FAKE_MODELS_DIR = os.path.join(TESTS_DIR, "fakes", "models")

DEFAULT_TIMEOUT = 5.0


# --------------------------------------------------------------------------
# Audio helpers
#
# Every helper returns a whole number of 1280-sample chunks. The engine slices
# audio on that boundary, so unaligned buffers would let a cancel marker be
# split across two predict() calls and silently stop matching.
# --------------------------------------------------------------------------

def _chunks_for(seconds):
    return max(1, round(seconds * SAMPLE_RATE / CHUNK_SAMPLES))


def silence(seconds=1.0):
    return np.zeros(_chunks_for(seconds) * CHUNK_SAMPLES, dtype=np.float32)


def speech(seconds=1.0, seed=0):
    """Noise loud enough to read as speech (mean |amplitude| well over 0.008)."""
    rng = np.random.default_rng(seed)
    samples = _chunks_for(seconds) * CHUNK_SAMPLES
    return (rng.standard_normal(samples).astype(np.float32) * 0.06).clip(-1.0, 1.0)


def cancel_word(chunks=1):
    """Audio the fake wake word model scores above threshold."""
    return np.full(chunks * CHUNK_SAMPLES, CANCEL_MARKER, dtype=np.float32)


# --------------------------------------------------------------------------
# Channels
# --------------------------------------------------------------------------

class AudioChannel:
    """TCP server the fake sounddevice connects to."""

    def __init__(self):
        self._server = socket.socket()
        self._server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server.bind(("127.0.0.1", 0))
        self._server.listen(4)
        self.endpoint = "127.0.0.1:%d" % self._server.getsockname()[1]

        self._conn = None
        self._lock = threading.Lock()
        self._opens = 0
        self._fail_opens = 0
        self._closed = False
        threading.Thread(target=self._accept_loop, daemon=True).start()

    @property
    def open_attempts(self):
        return self._opens

    def fail_next_opens(self, count):
        """Make the next `count` stream opens raise PortAudioError."""
        with self._lock:
            self._fail_opens = count

    def _accept_loop(self):
        while not self._closed:
            try:
                conn, _ = self._server.accept()
            except OSError:
                return
            with self._lock:
                self._opens += 1
                should_fail = self._fail_opens > 0
                if should_fail:
                    self._fail_opens -= 1
                else:
                    self._conn = conn
            try:
                conn.sendall(bytes([1 if should_fail else 0]))
            except OSError:
                pass
            if should_fail:
                conn.close()

    def wait_connected(self, timeout=DEFAULT_TIMEOUT):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            with self._lock:
                if self._conn is not None:
                    return
            time.sleep(0.01)
        raise AssertionError("engine never opened the audio stream")

    def push(self, *arrays):
        """Send audio to the engine, faster than realtime."""
        buf = np.concatenate([np.asarray(a, dtype=np.float32) for a in arrays])
        assert len(buf) % CHUNK_SAMPLES == 0, (
            "audio must be a whole number of %d-sample chunks; got %d"
            % (CHUNK_SAMPLES, len(buf))
        )
        payload = buf.tobytes()
        with self._lock:
            conn = self._conn
        if conn is None:
            raise AssertionError("no audio stream is open")
        conn.sendall(struct.pack("!I", len(payload)) + payload)

    def simulate_device_loss(self):
        """Stop delivering audio, as PortAudio does when the input device goes away.

        The stream object stays "open" from the engine's point of view; the
        callback simply never fires again.
        """
        with self._lock:
            conn, self._conn = self._conn, None
        if conn is None:
            raise AssertionError("no audio stream is open")
        conn.close()

    def close(self):
        self._closed = True
        with self._lock:
            if self._conn:
                self._conn.close()
        self._server.close()


class WhisperCall:
    def __init__(self, payload, respond):
        self.payload = payload
        self.op = payload.get("op")
        self.samples = payload.get("samples")
        self.language = payload.get("language")
        self._respond = respond
        self._answered = False

    def reply(self, **fields):
        assert not self._answered, "call already answered"
        self._answered = True
        self._respond(fields)


class WhisperControl:
    """TCP server the fake faster_whisper calls back into.

    In auto mode (the default) calls are answered immediately with `text` and
    recorded for later assertions. In manual mode they queue up and block until
    the test replies, which is how tests position audio mid-transcription.
    """

    def __init__(self):
        self._server = socket.socket()
        self._server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server.bind(("127.0.0.1", 0))
        self._server.listen(2)
        self.endpoint = "127.0.0.1:%d" % self._server.getsockname()[1]

        self.recorded = []
        self.text = "hello world"
        self.probs = {"en": 0.9, "pl": 0.05}
        self._manual = False
        self._pending = queue.Queue()
        self._lock = threading.Lock()
        self._closed = False
        threading.Thread(target=self._accept_loop, daemon=True).start()

    def manual(self, enabled=True):
        self._manual = enabled

    def calls(self, op):
        return [c for c in self.recorded if c.get("op") == op]

    def await_call(self, op="transcribe", timeout=DEFAULT_TIMEOUT):
        deadline = time.monotonic() + timeout
        held = []
        try:
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise AssertionError("no %s call arrived within %.1fs" % (op, timeout))
                try:
                    call = self._pending.get(timeout=remaining)
                except queue.Empty:
                    raise AssertionError("no %s call arrived within %.1fs" % (op, timeout))
                if call.op == op:
                    return call
                held.append(call)
        finally:
            for call in held:
                self._pending.put(call)

    def _accept_loop(self):
        while not self._closed:
            try:
                conn, _ = self._server.accept()
            except OSError:
                return
            threading.Thread(target=self._serve, args=(conn,), daemon=True).start()

    def _serve(self, conn):
        while not self._closed:
            try:
                header = self._recv_exact(conn, 4)
                (length,) = struct.unpack("!I", header)
                payload = json.loads(self._recv_exact(conn, length).decode("utf-8"))
            except (ConnectionError, OSError, ValueError):
                return

            with self._lock:
                self.recorded.append(payload)

            def respond(fields, conn=conn):
                body = json.dumps(fields).encode("utf-8")
                try:
                    conn.sendall(struct.pack("!I", len(body)) + body)
                except OSError:
                    pass

            call = WhisperCall(payload, respond)
            if payload.get("op") == "load":
                call.reply()
            elif self._manual:
                self._pending.put(call)
            else:
                call.reply(**self._default_reply(payload))

    def _default_reply(self, payload):
        if payload.get("op") == "detect_language":
            return {"probs": self.probs}
        return {"text": self.text}

    @staticmethod
    def _recv_exact(sock, count):
        buf = bytearray()
        while len(buf) < count:
            part = sock.recv(count - len(buf))
            if not part:
                raise ConnectionError("control channel closed")
            buf.extend(part)
        return bytes(buf)

    def close(self):
        self._closed = True
        self._server.close()


# --------------------------------------------------------------------------
# Event stream
# --------------------------------------------------------------------------

class EventStream:
    def __init__(self):
        self._queue = queue.Queue()
        self.seen = []

    def push(self, event):
        self._queue.put(event)

    def next(self, timeout=DEFAULT_TIMEOUT):
        try:
            event = self._queue.get(timeout=timeout)
        except queue.Empty:
            return None
        self.seen.append(event)
        return event

    def expect(self, *names, timeout=DEFAULT_TIMEOUT):
        """Match `names` as an ordered subsequence, ignoring events in between.

        Returns the matched events. Asserting on a subsequence rather than an
        exact list keeps tests from breaking when an unrelated event is added.
        """
        deadline = time.monotonic() + timeout
        matched = []
        for name in names:
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise AssertionError(
                        "timed out waiting for %r (matched %d/%d)\nsaw: %s"
                        % (name, len(matched), len(names), self._log())
                    )
                event = self.next(timeout=remaining)
                if event is None:
                    raise AssertionError(
                        "timed out waiting for %r (matched %d/%d)\nsaw: %s"
                        % (name, len(matched), len(names), self._log())
                    )
                if event.get("event") == name:
                    matched.append(event)
                    break
        return matched[0] if len(matched) == 1 else matched

    def expect_not(self, *names, within=1.0):
        """Assert none of `names` appears in the next `within` seconds."""
        deadline = time.monotonic() + within
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return
            event = self.next(timeout=remaining)
            if event is None:
                return
            if event.get("event") in names:
                raise AssertionError(
                    "unexpected %r\nsaw: %s" % (event.get("event"), self._log())
                )

    def drain(self, quiet_for=0.3, timeout=DEFAULT_TIMEOUT):
        """Consume events until the stream goes quiet."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.next(timeout=quiet_for) is None:
                return

    def _log(self):
        return ", ".join(e.get("event", "?") for e in self.seen[-15:]) or "(nothing)"


# --------------------------------------------------------------------------
# Engine
# --------------------------------------------------------------------------

class Engine:
    def __init__(self, languages="en", cancel_word="hey_jarvis", stub_models=True):
        self.languages = languages
        self.cancel_word = cancel_word
        self.stub_models = stub_models

        self.audio = AudioChannel()
        self.whisper = WhisperControl() if stub_models else None
        self.events = EventStream()
        self.process = None
        self._stderr = []

    def start(self):
        path_parts = [FAKE_AUDIO_DIR]
        if self.stub_models:
            path_parts.append(FAKE_MODELS_DIR)
        if os.environ.get("PYTHONPATH"):
            path_parts.append(os.environ["PYTHONPATH"])

        env = dict(os.environ)
        env["PYTHONPATH"] = os.pathsep.join(path_parts)
        env["PYTHONUNBUFFERED"] = "1"
        env["OVERHEAR_TEST_AUDIO"] = self.audio.endpoint
        env["OVERHEAR_TEST_CANCEL_MARKER"] = repr(CANCEL_MARKER)
        if self.whisper:
            env["OVERHEAR_TEST_CONTROL"] = self.whisper.endpoint

        self.process = subprocess.Popen(
            [ENGINE_PYTHON, "-u", ENGINE_PATH,
             "--languages", self.languages,
             "--cancel-word", self.cancel_word],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            cwd=REPO_ROOT,
        )
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()
        return self

    def _read_stdout(self):
        for raw in self.process.stdout:
            line = raw.decode("utf-8").strip()
            if not line:
                continue
            try:
                self.events.push(json.loads(line))
            except json.JSONDecodeError:
                self.events.push({"event": "__unparseable__", "raw": line})

    def _read_stderr(self):
        for raw in self.process.stderr:
            self._stderr.append(raw.decode("utf-8", "replace").rstrip())

    @property
    def stderr(self):
        return "\n".join(self._stderr)

    def send_raw(self, line):
        self.process.stdin.write((line + "\n").encode("utf-8"))
        self.process.stdin.flush()

    def send(self, command):
        self.send_raw(json.dumps({"command": command}))

    def wait_until_idle(self, timeout=DEFAULT_TIMEOUT):
        self.events.expect("idle", timeout=timeout)
        self.audio.wait_connected()
        return self

    def activate(self, timeout=DEFAULT_TIMEOUT):
        """Activate and wait for `ready`.

        The engine only notices the activate command after pulling a chunk off
        the audio queue, so this feeds silence until dictation actually starts —
        the same thing a live microphone would be doing.
        """
        self.send("activate")
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.audio.push(silence(0.16))
            event = self.events.next(timeout=0.2)
            if event and event.get("event") == "ready":
                return self
            if event and event.get("event") == "error":
                raise AssertionError("engine errored during activate: %s" % event)
        raise AssertionError("engine never became ready\nsaw: %s" % self.events._log())

    def deactivate(self, timeout=DEFAULT_TIMEOUT):
        self.send("deactivate")
        self.events.expect("idle", timeout=timeout)
        return self

    def wait_exit(self, timeout=DEFAULT_TIMEOUT):
        try:
            return self.process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            raise AssertionError("engine did not exit within %.1fs" % timeout)

    def close(self):
        if self.process and self.process.poll() is None:
            try:
                self.send("quit")
                self.process.wait(timeout=2)
            except (OSError, ValueError, subprocess.TimeoutExpired):
                pass
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait(timeout=2)
        self.audio.close()
        if self.whisper:
            self.whisper.close()
