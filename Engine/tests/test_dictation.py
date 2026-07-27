"""A3–A7 — batching, silence detection, and the shape of a dictation session."""

from .constants import CHUNK_SAMPLES, MAX_BATCH_DURATION, SAMPLE_RATE
from .harness import silence, speech


def test_one_utterance_produces_one_transcription(engine):
    """A3 — the full happy path for a single batch."""
    engine.activate()
    engine.audio.push(speech(1.0), silence(1.8))

    engine.events.expect("speech_start", "transcribing", "language_detected")
    transcription = engine.events.expect("transcription")
    assert transcription["text"] == "hello world"

    # and the engine re-arms for the next utterance
    engine.events.expect("ready")


def test_transcribe_is_called_with_the_documented_parameters(engine):
    """A3 — beam size, VAD, and language reach faster-whisper intact."""
    engine.activate()
    engine.audio.push(speech(1.0), silence(1.8))
    engine.events.expect("transcription")

    calls = engine.whisper.calls("transcribe")
    assert len(calls) == 1
    assert calls[0]["beam_size"] == 5
    assert calls[0]["vad_filter"] is True
    assert calls[0]["language"] == "en"


def test_consecutive_batches_stay_in_dictation(engine):
    """A4 — two utterances transcribe independently, with no drop to idle."""
    engine.activate()
    engine.audio.push(speech(0.8, seed=1), silence(1.8))
    engine.events.expect("transcription")

    engine.audio.push(speech(0.8, seed=2), silence(1.8))
    engine.events.expect("transcription")

    assert len(engine.whisper.calls("transcribe")) == 2
    engine.events.expect_not("idle", within=0.3)


def test_silence_alone_never_starts_a_batch(engine):
    """A6 — background silence must not trigger speech detection."""
    engine.activate()
    engine.audio.push(silence(5.0))

    engine.events.expect_not("speech_start", "transcribing", "transcription", within=1.5)


def test_batch_is_capped_at_max_duration(engine):
    """A7 — continuous speech is cut into batches rather than growing forever."""
    engine.activate()
    engine.audio.push(speech(MAX_BATCH_DURATION + 4))

    engine.events.expect("speech_start", "transcribing", "transcription")

    call = engine.whisper.calls("transcribe")[0]
    expected = int(MAX_BATCH_DURATION / (CHUNK_SAMPLES / SAMPLE_RATE)) * CHUNK_SAMPLES
    assert call["samples"] == expected

    # dictation continues rather than ending after the forced cut
    engine.events.expect("ready")


def test_very_short_utterance_still_transcribes(engine):
    """A5 — a brief utterance is transcribed like any other, by design.

    There is deliberately no minimum-duration filter. Measured against the real
    model, non-vocal noise is stripped by Whisper's VAD and yields empty text, so
    a threshold would buy nothing there; and real one-word utterances — "no",
    "what", "yeah" — sit within milliseconds of 0.3s, so a threshold set to catch
    interjections would eat legitimate dictation instead.
    """
    engine.activate()
    engine.audio.push(speech(0.16), silence(1.8))

    engine.events.expect("speech_start", "transcribing", "transcription")

    # The batch carries its trailing silence, so it is never actually short.
    call = engine.whisper.calls("transcribe")[0]
    assert call["samples"] > SAMPLE_RATE * 0.3
