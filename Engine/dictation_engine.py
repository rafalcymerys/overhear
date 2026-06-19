#!/usr/bin/env python3
"""
Dictation engine: wake word detection (openwakeword) + transcription (faster-whisper).
Communicates with the Swift host via JSON lines on stdin/stdout.
"""

import sys
import json
import signal
import threading
import queue
import time
import tempfile
import os
import numpy as np
import sounddevice as sd

SAMPLE_RATE = 16000
CHUNK_DURATION = 0.08  # 80ms chunks for wake word
CHUNK_SAMPLES = int(SAMPLE_RATE * CHUNK_DURATION)
SILENCE_THRESHOLD = 0.01
SILENCE_DURATION = 1.5  # seconds of silence to stop recording
MAX_RECORD_DURATION = 30  # max seconds of recording

audio_queue = queue.Queue()
running = True


def emit(event: dict):
    line = json.dumps(event, ensure_ascii=False)
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def audio_callback(indata, frames, time_info, status):
    if status:
        emit({"event": "warning", "message": str(status)})
    audio_queue.put(indata[:, 0].copy())


def is_silence(audio_chunk, threshold=SILENCE_THRESHOLD):
    return np.abs(audio_chunk).mean() < threshold


def record_utterance():
    """Record audio until silence is detected or max duration reached."""
    emit({"event": "recording_start"})
    chunks = []
    silence_chunks = 0
    silence_needed = int(SILENCE_DURATION / CHUNK_DURATION)
    max_chunks = int(MAX_RECORD_DURATION / CHUNK_DURATION)

    while len(chunks) < max_chunks:
        try:
            chunk = audio_queue.get(timeout=1.0)
        except queue.Empty:
            continue

        chunks.append(chunk)

        if is_silence(chunk):
            silence_chunks += 1
            if silence_chunks >= silence_needed and len(chunks) > silence_needed:
                break
        else:
            silence_chunks = 0

    emit({"event": "recording_stop", "duration": len(chunks) * CHUNK_DURATION})
    if chunks:
        return np.concatenate(chunks)
    return None


def transcribe(model, audio_data):
    """Transcribe audio using faster-whisper."""
    emit({"event": "transcribing"})

    segments, info = model.transcribe(
        audio_data,
        beam_size=5,
        language=None,
        vad_filter=True,
        vad_parameters=dict(
            min_silence_duration_ms=500,
            speech_pad_ms=200,
        ),
    )

    text_parts = []
    for segment in segments:
        text_parts.append(segment.text.strip())

    text = " ".join(text_parts).strip()
    return text


def command_listener():
    """Listen for commands from Swift host on stdin."""
    global running
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            cmd = json.loads(line)
            if cmd.get("command") == "quit":
                running = False
                return
        except json.JSONDecodeError:
            pass


def main():
    global running

    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))

    emit({"event": "status", "message": "loading_models"})

    try:
        from openwakeword.model import Model as OWWModel
        import openwakeword
        openwakeword.utils.download_models()
        oww = OWWModel(inference_framework="onnx")
        emit({"event": "status", "message": "wake_word_ready"})
    except Exception as e:
        emit({"event": "error", "message": f"Failed to load openwakeword: {e}"})
        sys.exit(1)

    try:
        from faster_whisper import WhisperModel
        whisper_model = WhisperModel("base", device="cpu", compute_type="int8")
        emit({"event": "status", "message": "whisper_ready"})
    except Exception as e:
        emit({"event": "error", "message": f"Failed to load whisper: {e}"})
        sys.exit(1)

    emit({"event": "ready"})

    cmd_thread = threading.Thread(target=command_listener, daemon=True)
    cmd_thread.start()

    try:
        with sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=1,
            dtype="float32",
            blocksize=CHUNK_SAMPLES,
            callback=audio_callback,
        ):
            emit({"event": "listening"})

            while running:
                try:
                    chunk = audio_queue.get(timeout=0.5)
                except queue.Empty:
                    continue

                chunk_int16 = (chunk * 32767).astype(np.int16)
                prediction = oww.predict(chunk_int16)

                for model_name, score in prediction.items():
                    if score > 0.5:
                        emit({
                            "event": "wake_word",
                            "model": model_name,
                            "score": float(score),
                        })
                        oww.reset()

                        audio_data = record_utterance()
                        if audio_data is not None and len(audio_data) > SAMPLE_RATE * 0.3:
                            text = transcribe(whisper_model, audio_data)
                            if text:
                                emit({"event": "transcription", "text": text})
                            else:
                                emit({"event": "transcription_empty"})
                        else:
                            emit({"event": "transcription_empty"})

                        emit({"event": "listening"})
                        break

    except Exception as e:
        emit({"event": "error", "message": str(e)})
        sys.exit(1)


if __name__ == "__main__":
    main()
