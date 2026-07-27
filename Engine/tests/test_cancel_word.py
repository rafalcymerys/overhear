"""A8–A10 — the cancel word, in both of the places the engine checks for it."""

import time

from .constants import CHUNK_SAMPLES
from .harness import cancel_word, silence, speech

# Local TCP delivery of a few chunks is fast, but the tests below need audio to
# have *arrived* in the engine's queue before they release the transcription.
# There is no event to wait on, so allow a generous margin.
DELIVERY_MARGIN = 0.3


def test_cancel_word_during_recording_drops_the_batch(engine):
    """A8 — speaking the cancel word mid-utterance discards it."""
    engine.activate()
    engine.audio.push(speech(0.5))
    engine.events.expect("speech_start")

    engine.audio.push(cancel_word())
    engine.events.expect("wake_word_cancel")
    engine.events.expect_not("transcribing", "transcription", within=0.5)

    assert engine.whisper.calls("transcribe") == []


def test_dictation_survives_a_cancel(engine):
    """A8 — after cancelling, the very next utterance transcribes normally.

    This is the regression test for the reset/drain in record_batch: leftover
    model state or leftover audio would either re-fire the cancel or leak the
    discarded audio into the following batch.
    """
    engine.activate()
    engine.audio.push(speech(0.5), cancel_word())
    engine.events.expect("wake_word_cancel")
    engine.events.expect("ready")

    engine.audio.push(speech(0.8), silence(1.8))
    transcription = engine.events.expect("transcription")
    assert transcription["text"] == "hello world"

    calls = engine.whisper.calls("transcribe")
    assert len(calls) == 1
    # the cancelled audio was dropped, not prepended to this batch
    assert calls[0]["samples"] < int(1.0 * 16000) + int(2.0 * 16000)


def test_cancel_word_before_any_speech(engine):
    """A8 — the cancel word is live even while waiting for an utterance."""
    engine.activate()
    engine.audio.push(cancel_word())

    engine.events.expect("wake_word_cancel")
    engine.events.expect_not("speech_start", within=0.3)


def test_cancel_word_during_transcription_suppresses_the_result(engine):
    """A9 — a cancel that lands while Whisper is running still takes effect.

    The transcription is held open until the cancel audio has been delivered, so
    this exercises check_queued_wake_word rather than racing against it.
    """
    engine.whisper.manual()
    engine.activate()
    engine.audio.push(speech(1.0), silence(1.8))

    call = engine.whisper.await_call("transcribe")
    engine.events.expect("speech_start", "transcribing")

    engine.audio.push(cancel_word())
    time.sleep(DELIVERY_MARGIN)
    call.reply(text="text the user cancelled")

    engine.events.expect("wake_word_cancel")
    engine.events.expect_not("transcription", within=0.5)


def test_audio_buffered_during_transcription_is_not_lost(engine):
    """A10 — speech spoken while Whisper is busy carries into the next batch.

    check_queued_wake_word drains the audio queue to inspect it; when it finds
    no cancel word it has to put every chunk back. If it did not, the first word
    after each transcription would be silently eaten.
    """
    engine.whisper.manual()
    engine.activate()
    engine.audio.push(speech(1.0), silence(1.8))

    first = engine.whisper.await_call("transcribe")
    engine.events.expect("transcribing")

    spoken_during = speech(0.8, seed=7)
    engine.audio.push(spoken_during)
    time.sleep(DELIVERY_MARGIN)
    first.reply(text="first utterance")

    engine.events.expect("transcription")

    # close the second batch and confirm it still contains the buffered audio
    engine.audio.push(silence(1.8))
    second = engine.whisper.await_call("transcribe")
    assert second.samples >= len(spoken_during)
    second.reply(text="second utterance")

    engine.events.expect("transcription")


def test_buffered_audio_keeps_its_place(engine):
    """A10 — the re-queued chunks are the whole of the next batch's speech."""
    engine.whisper.manual()
    engine.activate()
    engine.audio.push(speech(1.0), silence(1.8))

    first = engine.whisper.await_call("transcribe")
    spoken_during = speech(0.8, seed=9)
    engine.audio.push(spoken_during)
    time.sleep(DELIVERY_MARGIN)
    first.reply(text="first")
    engine.events.expect("transcription")

    trailing = silence(1.8)
    engine.audio.push(trailing)
    second = engine.whisper.await_call("transcribe")

    expected = len(spoken_during) + len(trailing)
    assert abs(second.samples - expected) <= CHUNK_SAMPLES
    second.reply(text="second")
