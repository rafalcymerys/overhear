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
    """Record one batch of speech until silence, max duration, or wake word (to cancel)."""
    chunks = []
    silence_chunks = 0
    silence_needed = int(SILENCE_DURATION / CHUNK_DURATION)
    max_chunks = int(MAX_BATCH_DURATION / CHUNK_DURATION)
    heard_speech = False

    while get_dictating() and len(chunks) < max_chunks:
        try:
            chunk = audio_queue.get(timeout=0.5)
        except queue.Empty:
            continue

        chunk_int16 = (chunk * 32767).astype(np.int16)
        prediction = oww.predict(chunk_int16)
        cancelled = False
        for _model_name, score in prediction.items():
            if score > 0.5:
                cancelled = True
                break
        if cancelled:
            oww.reset()
            emit({"event": "wake_word_cancel"})
            while not audio_queue.empty():
                try:
                    audio_queue.get_nowait()
                except queue.Empty:
                    break
            return None

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


def check_queued_wake_word(oww):
    """Check if wake word exists in audio buffered during transcription."""
    chunks = []
    while not audio_queue.empty():
        try:
            chunks.append(audio_queue.get_nowait())
        except queue.Empty:
            break

    found = False
    for chunk in chunks:
        chunk_int16 = (chunk * 32767).astype(np.int16)
        prediction = oww.predict(chunk_int16)
        for _, score in prediction.items():
            if score > 0.5:
                found = True
                break
        if found:
            break

    if found:
        oww.reset()
        while not audio_queue.empty():
            try:
                audio_queue.get_nowait()
            except queue.Empty:
                break
        return True

    for chunk in chunks:
        audio_queue.put(chunk)
    return False


def detect_language(model, audio_data, languages):
    """Detect language from audio, constrained to the given set."""
    _lang, _prob, all_probs = model.detect_language(audio_data)
    prob_map = {code: prob for code, prob in all_probs}
    best_lang = max(languages, key=lambda l: prob_map.get(l, 0.0))
    return best_lang


def transcribe(model, audio_data, languages=None):
    """Transcribe audio using faster-whisper.

    Detects the most likely language from the selected set, then
    transcribes with that language explicitly for best accuracy.
    """
    if languages and len(languages) == 1:
        lang = languages[0]
    elif languages and len(languages) > 1:
        lang = detect_language(model, audio_data, languages)
    else:
        lang = None

    segments, info = model.transcribe(
        audio_data,
        beam_size=5,
        language=lang,
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

    detected = lang or getattr(info, "language", None)
    if detected and text:
        emit({"event": "language_detected", "language": detected})

    return text


def dictation_loop(whisper_model, oww, languages=None):
    """Continuously record and transcribe batches while dictating."""
    while get_dictating() and running:
        emit({"event": "ready"})
        audio_data = record_batch(oww)
        if audio_data is not None and len(audio_data) > SAMPLE_RATE * 0.3:
            emit({"event": "transcribing"})
            text = transcribe(whisper_model, audio_data, languages)
            if check_queued_wake_word(oww):
                emit({"event": "wake_word_cancel"})
                continue
            if text:
                emit({"event": "transcription", "text": text})


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


def parse_languages():
    """Parse --languages argument."""
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--languages", type=str, default="en")
    args = parser.parse_args()
    langs = [l.strip() for l in args.languages.split(",") if l.strip()]
    return langs if langs else ["en"]


def main():
    global running

    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))

    languages = parse_languages()
    emit({"event": "status", "message": "loading_models"})
    emit({"event": "config", "languages": languages})

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

    emit({"event": "idle"})

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
            while running:
                try:
                    chunk = audio_queue.get(timeout=0.5)
                except queue.Empty:
                    continue

                if get_dictating():
                    audio_queue.put(chunk)
                    dictation_loop(whisper_model, oww, languages)
                    if running:
                        oww.reset()
                        emit({"event": "idle"})
                    continue

    except Exception as e:
        emit({"event": "error", "message": str(e)})
        sys.exit(1)


if __name__ == "__main__":
    main()
