"""Fake `faster_whisper` module driven by an RPC channel back to the test.

Every call to detect_language() / transcribe() becomes a request on a TCP
connection to the harness, and blocks until the harness replies. That gives
tests two things a canned stub cannot:

  - the exact moment transcription *starts* (the request arrives), so audio can
    be pushed while the engine believes it is busy;
  - control over when it *finishes* (the reply is sent), so "audio arrived
    during transcription" is a guaranteed ordering rather than a race.

Requests also carry the sample count and requested language, which is how tests
assert on batching and language selection without inspecting engine internals.
"""

import json
import os
import socket
import struct
import threading

_lock = threading.Lock()
_sock = None


def _connect():
    global _sock
    if _sock is None:
        host, port = os.environ["OVERHEAR_TEST_CONTROL"].rsplit(":", 1)
        _sock = socket.create_connection((host, int(port)))
    return _sock


def _recv_exact(sock, count):
    buf = bytearray()
    while len(buf) < count:
        part = sock.recv(count - len(buf))
        if not part:
            raise ConnectionError("test control channel closed")
        buf.extend(part)
    return bytes(buf)


def _rpc(payload):
    with _lock:
        sock = _connect()
        body = json.dumps(payload).encode("utf-8")
        sock.sendall(struct.pack("!I", len(body)) + body)
        (length,) = struct.unpack("!I", _recv_exact(sock, 4))
        return json.loads(_recv_exact(sock, length).decode("utf-8"))


class Segment:
    def __init__(self, text):
        self.text = text


class TranscriptionInfo:
    def __init__(self, language, language_probability=1.0):
        self.language = language
        self.language_probability = language_probability


class WhisperModel:
    def __init__(self, model_size_or_path, device=None, compute_type=None, **_kwargs):
        self.model_size = model_size_or_path
        self.device = device
        self.compute_type = compute_type
        _rpc({"op": "load", "model": model_size_or_path,
              "device": device, "compute_type": compute_type})

    def detect_language(self, audio):
        reply = _rpc({"op": "detect_language", "samples": int(len(audio))})
        probs = reply.get("probs", {"en": 1.0})
        ordered = sorted(probs.items(), key=lambda kv: kv[1], reverse=True)
        best, best_prob = ordered[0]
        return best, best_prob, ordered

    def transcribe(self, audio, beam_size=None, language=None,
                   vad_filter=None, vad_parameters=None, **_kwargs):
        reply = _rpc({
            "op": "transcribe",
            "samples": int(len(audio)),
            "language": language,
            "beam_size": beam_size,
            "vad_filter": bool(vad_filter),
        })
        segments = reply.get("segments")
        if segments is None:
            text = reply.get("text", "")
            segments = [text] if text else []
        info = TranscriptionInfo(reply.get("info_language", language or "en"))
        return iter([Segment(s) for s in segments]), info
