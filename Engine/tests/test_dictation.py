"""A3–A7 — batching, silence detection, and the shape of a dictation session."""

import pytest

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
    """A5 — documents that the 0.3s minimum-length guard is unreachable.

    dictation_loop only transcribes batches longer than 0.3s, but record_batch
    accumulates the trailing silence into the same batch — so any batch that
    closes normally is at least 18 silent chunks (1.4s) long and always clears
    the bar. A 160ms cough is transcribed like anything else, and whatever
    Whisper hallucinates from it gets pasted.
    """
    engine.activate()
    engine.audio.push(speech(0.16), silence(1.8))

    engine.events.expect("speech_start", "transcribing", "transcription")

    call = engine.whisper.calls("transcribe")[0]
    assert call["samples"] > SAMPLE_RATE * 0.3


@pytest.mark.xfail(reason="known gap: no minimum speech duration, so brief noise "
                          "is transcribed and pasted", strict=True)
def test_very_short_utterance_should_be_discarded(engine):
    """A5b — the behaviour the 0.3s guard was presumably meant to provide."""
    engine.activate()
    engine.audio.push(speech(0.16), silence(1.8))

    engine.events.expect_not("transcribing", within=1.5)
