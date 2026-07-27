"""A14 — what happens when the audio device misbehaves."""

import pytest

from .harness import silence, speech


def test_stream_that_fails_to_open_is_retried(engine_factory):
    """A14a — a device that cannot be opened is reported and retried."""
    engine = engine_factory(start=False)
    engine.audio.fail_next_opens(1)
    engine.start()

    warning = engine.events.expect("warning", timeout=10.0)
    assert "Audio device changed" in warning["message"]

    engine.events.expect("idle", timeout=10.0)
    assert engine.audio.open_attempts == 2


def test_repeated_open_failures_keep_retrying(engine_factory):
    """A14a — the retry loop does not give up after one attempt."""
    engine = engine_factory(start=False)
    engine.audio.fail_next_opens(3)
    engine.start()

    engine.events.expect("warning", "warning", "warning", timeout=15.0)
    engine.events.expect("idle", timeout=10.0)
    assert engine.audio.open_attempts == 4


def test_engine_recovers_enough_to_dictate(engine_factory):
    """A14a — after a failed open, the engine is fully functional."""
    engine = engine_factory(start=False)
    engine.audio.fail_next_opens(1)
    engine.start()
    engine.wait_until_idle(timeout=10.0)

    engine.activate()
    engine.audio.push(speech(1.0), silence(1.8))
    assert engine.events.expect("transcription")["text"] == "hello world"


@pytest.mark.xfail(reason="known bug: a device that stops delivering audio mid-session "
                          "is never noticed — the engine waits forever", strict=True)
def test_device_lost_mid_dictation_is_reported(engine):
    """A14b — losing the microphone during dictation should surface somehow.

    It does not. PortAudioError can only be raised from InputStream.start(), and
    the engine's inner loop never touches the stream — it only blocks on
    audio_queue.get(timeout=0.5). So when the device goes away the callback
    simply stops firing, the loop spins on timeouts forever, and the app keeps
    showing "Ready" while hearing nothing.

    A fix would need a watchdog: if N consecutive gets time out while dictating,
    tear the stream down and re-open it.
    """
    engine.activate()
    engine.audio.simulate_device_loss()

    engine.events.expect("warning", timeout=5.0)
