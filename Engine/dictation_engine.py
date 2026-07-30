#!/usr/bin/env python3
"""
Dictation engine: cancel word detection (openwakeword) + transcription (faster-whisper).
Communicates with the Swift host via JSON lines on stdin/stdout.

Flow:
  - Idle: capturing audio but doing nothing with it, waiting for a command
  - "activate" command → enter dictation mode
  - Dictation mode: continuously record speech in batches, transcribe each
    batch on silence, emit the text for the host to paste, keep listening
  - Cancel word → discard the current batch, stay in dictation mode
  - "deactivate" command → back to idle

The cancel word model is chosen with --cancel-word (a built-in openwakeword
name, or a path to an .onnx file); the language set with --languages.
"""

import sys
import json
import signal
import threading
import time
import queue
import numpy as np
import sounddevice as sd

SAMPLE_RATE = 16000
CHUNK_SAMPLES = 1280  # 80ms at 16kHz, what openwakeword expects
CHUNK_DURATION = CHUNK_SAMPLES / SAMPLE_RATE
SILENCE_THRESHOLD = 0.008
SILENCE_DURATION = 1.5  # seconds of silence to end a batch
MAX_BATCH_DURATION = 30  # max seconds per batch

# How long the input stream may go without delivering a single buffer before we
# treat the device as gone. Audio arrives every 80ms while a stream is healthy —
# even during silence — so this is a wide margin that still notices a lost
# device within a few seconds.
AUDIO_TIMEOUT = 3.0

audio_queue = queue.Queue()
running = True
dictating = False
dictating_lock = threading.Lock()
last_audio_time = 0.0


class AudioDeviceLost(Exception):
    """The input stream stopped delivering audio without reporting an error.

    PortAudio only raises through the API when a stream is opened or explicitly
    operated on. When the default input device disappears mid-session it simply
    stops invoking the callback, so nothing would ever surface without this.
    """


def emit(event: dict):
    line = json.dumps(event, ensure_ascii=False)
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def audio_callback(indata, frames, time_info, status):
    global last_audio_time
    last_audio_time = time.monotonic()
    if status:
        emit({"event": "warning", "message": str(status)})
    audio_queue.put(indata[:, 0].copy())


def check_audio_alive():
    """Raise if the input stream has gone quiet for longer than AUDIO_TIMEOUT.

    Called wherever the engine waits on the audio queue, so a lost device is
    noticed whether it happens mid-utterance or while idle.
    """
    silent_for = time.monotonic() - last_audio_time
    if silent_for > AUDIO_TIMEOUT:
        raise AudioDeviceLost(f"no audio for {silent_for:.1f}s")


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
    """Record one batch of speech.

    Returns audio only if the batch actually finished — on trailing silence or
    the duration cap. If dictation was stopped mid-utterance the audio is
    dropped: the user asked to stop, so nothing more should reach their
    document. The wake word cancels by returning None from inside the loop.
    """
    chunks = []
    silence_chunks = 0
    silence_needed = int(SILENCE_DURATION / CHUNK_DURATION)
    max_chunks = int(MAX_BATCH_DURATION / CHUNK_DURATION)
    heard_speech = False
    completed = False

    while get_dictating():
        if len(chunks) >= max_chunks:
            completed = True
            break

        try:
            chunk = audio_queue.get(timeout=0.5)
        except queue.Empty:
            check_audio_alive()
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
                completed = True
                break
        else:
            silence_chunks = 0

    if completed and chunks and heard_speech:
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
        # No minimum length check. record_batch only returns completed batches,
        # which always carry their trailing silence and so are never short. A
        # duration threshold would also be the wrong tool: measured against real
        # speech, "no", "what" and "yeah" all land within a few milliseconds of
        # 0.3s, so any such cut would eat legitimate one-word dictation. Whisper's
        # VAD already discards non-vocal noise, leaving empty text that the check
        # below drops.
        if audio_data is not None:
            emit({"event": "transcribing"})
            text = transcribe(whisper_model, audio_data, languages)
            if check_queued_wake_word(oww):
                emit({"event": "wake_word_cancel"})
                continue
            # Transcription can outlive a stop request — Whisper runs for about a
            # second. Dropping the result keeps the promise that nothing reaches
            # the user's document after they press Stop.
            if text and get_dictating():
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


def parse_args():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--languages", type=str, default="en")
    parser.add_argument("--cancel-word", type=str, default="alexa")
    args = parser.parse_args()
    langs = [l.strip() for l in args.languages.split(",") if l.strip()]
    langs = langs if langs else ["en"]
    return langs, args.cancel_word


def main():
    global running

    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))

    languages, cancel_word = parse_args()
    emit({"event": "status", "message": "loading_models"})
    emit({"event": "config", "languages": languages})

    try:
        from openwakeword.model import Model as OWWModel
        import openwakeword
        openwakeword.utils.download_models()
        oww = OWWModel(wakeword_models=[cancel_word], inference_framework="onnx")
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

    cmd_thread = threading.Thread(target=command_listener, daemon=True)
    cmd_thread.start()

    global last_audio_time

    while running:
        try:
            # Start the clock before opening, so a stream that never delivers a
            # single buffer is caught by the same watchdog.
            last_audio_time = time.monotonic()

            with sd.InputStream(
                samplerate=SAMPLE_RATE,
                channels=1,
                dtype="float32",
                blocksize=CHUNK_SAMPLES,
                callback=audio_callback,
            ):
                emit({"event": "idle"})

                while running:
                    try:
                        chunk = audio_queue.get(timeout=0.5)
                    except queue.Empty:
                        check_audio_alive()
                        continue

                    if get_dictating():
                        audio_queue.put(chunk)
                        dictation_loop(whisper_model, oww, languages)
                        if running:
                            oww.reset()
                            emit({"event": "idle"})
                        continue

        except (sd.PortAudioError, AudioDeviceLost) as e:
            emit({"event": "warning", "message": f"Audio device changed: {e}"})
            set_dictating(False)
            while not audio_queue.empty():
                try:
                    audio_queue.get_nowait()
                except queue.Empty:
                    break
            time.sleep(1)
        except Exception as e:
            emit({"event": "error", "message": str(e)})
            sys.exit(1)


if __name__ == "__main__":
    main()
