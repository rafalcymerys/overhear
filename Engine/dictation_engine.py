#!/usr/bin/env python3
"""
Dictation engine: wake word detection (openwakeword) + transcription (faster-whisper).
Communicates with the Swift host via JSON lines on stdin/stdout.

Flow:
  - Idle: listening for wake word
  - Wake word detected → enter dictation mode
  - Dictation mode: continuously record speech in batches, transcribe each
    batch on silence, inject text, keep listening for more speech
  - Wake word again OR "deactivate" command → back to idle
"""

import sys
import json
import signal
import threading
import queue
import numpy as np
import sounddevice as sd

SAMPLE_RATE = 16000
CHUNK_SAMPLES = 1280  # 80ms at 16kHz, what openwakeword expects
CHUNK_DURATION = CHUNK_SAMPLES / SAMPLE_RATE
SILENCE_THRESHOLD = 0.008
SILENCE_DURATION = 1.5  # seconds of silence to end a batch
MAX_BATCH_DURATION = 30  # max seconds per batch

audio_queue = queue.Queue()
running = True
dictating = False
dictating_lock = threading.Lock()


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


def set_dictating(value):
    global dictating
    with dictating_lock:
        dictating = value


def get_dictating():
    with dictating_lock:
        return dictating


def record_batch(oww):
    """Record one batch of speech until silence, max duration, or wake word (to stop)."""
    chunks = []
    silence_chunks = 0
    silence_needed = int(SILENCE_DURATION / CHUNK_DURATION)
    max_chunks = int(MAX_BATCH_DURATION / CHUNK_DURATION)
    heard_speech = False
    stopped_by_wake_word = False

    while get_dictating() and len(chunks) < max_chunks:
        try:
            chunk = audio_queue.get(timeout=0.5)
        except queue.Empty:
            continue

        # Check for wake word to toggle off
        chunk_int16 = (chunk * 32767).astype(np.int16)
        prediction = oww.predict(chunk_int16)
        for _model_name, score in prediction.items():
            if score > 0.5:
                stopped_by_wake_word = True
                break
        if stopped_by_wake_word:
            oww.reset()
            set_dictating(False)
            emit({"event": "wake_word_off"})
            break

        chunks.append(chunk)
        quiet = is_silence(chunk)

        if not quiet and not heard_speech:
            heard_speech = True
            emit({"event": "speech_start"})

        if heard_speech and quiet:
            silence_chunks += 1
            if silence_chunks >= silence_needed:
                break
        else:
            silence_chunks = 0

    if chunks and heard_speech:
        return np.concatenate(chunks)
    return None


def transcribe(model, audio_data):
    """Transcribe audio using faster-whisper."""
    segments, _info = model.transcribe(
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
    return " ".join(text_parts).strip()


def dictation_loop(whisper_model, oww):
    """Continuously record and transcribe batches while dictating."""
    while get_dictating() and running:
        audio_data = record_batch(oww)
        if not get_dictating():
            break
        if audio_data is not None and len(audio_data) > SAMPLE_RATE * 0.3:
            emit({"event": "transcribing"})
            text = transcribe(whisper_model, audio_data)
            if text:
                emit({"event": "transcription", "text": text})
            emit({"event": "dictating"})


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
                set_dictating(False)
                running = False
                return
            elif cmd.get("command") == "deactivate":
                set_dictating(False)
            elif cmd.get("command") == "activate":
                set_dictating(True)
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

                if get_dictating():
                    # Already in dictation mode (activated via command),
                    # push chunk back and run dictation loop
                    audio_queue.put(chunk)
                    emit({"event": "dictating"})
                    dictation_loop(whisper_model, oww)
                    if running:
                        oww.reset()
                        emit({"event": "listening"})
                    continue

                # Check for wake word
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
                        set_dictating(True)
                        emit({"event": "dictating"})

                        # Drain the queue of wake word audio
                        while not audio_queue.empty():
                            try:
                                audio_queue.get_nowait()
                            except queue.Empty:
                                break

                        dictation_loop(whisper_model, oww)

                        if running:
                            oww.reset()
                            emit({"event": "listening"})
                        break

    except Exception as e:
        emit({"event": "error", "message": str(e)})
        sys.exit(1)


if __name__ == "__main__":
    main()
