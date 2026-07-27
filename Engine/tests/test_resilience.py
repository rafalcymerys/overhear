"""A14 — what happens when the audio device misbehaves."""

import time

from .constants import AUDIO_TIMEOUT
from .harness import silence, speech

# The watchdog needs AUDIO_TIMEOUT of quiet before it fires, plus a queue poll
# and the one-second reopen delay.
DEVICE_LOSS_TIMEOUT = AUDIO_TIMEOUT + 5.0


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


def test_device_lost_mid_dictation_is_reported(engine):
    """A14b — losing the microphone during dictation is noticed and reported.

    PortAudio never raises for this: when the default input device disappears it
    just stops invoking the callback. The watchdog in check_audio_alive() is what
    turns that silence into an error the engine can act on.
    """
    engine.activate()
    engine.audio.simulate_device_loss()

    warning = engine.events.expect("warning", timeout=DEVICE_LOSS_TIMEOUT)
    assert "Audio device changed" in warning["message"]


def test_device_lost_while_idle_is_reported(engine):
    """A14b — the watchdog covers the idle loop too, not just dictation."""
    engine.audio.simulate_device_loss()

    engine.events.expect("warning", timeout=DEVICE_LOSS_TIMEOUT)


def test_engine_recovers_on_the_replacement_device(engine):
    """A14b — a fresh stream is opened and dictation works on it again.

    Dictation itself does not survive the swap: the user has to start again,
    which is the same contract as a stream that fails to open.
    """
    engine.activate()
    opens_before = engine.audio.open_attempts

    engine.audio.simulate_device_loss()
    engine.events.expect("warning", timeout=DEVICE_LOSS_TIMEOUT)
    engine.wait_until_idle(timeout=DEVICE_LOSS_TIMEOUT)

    assert engine.audio.open_attempts > opens_before, "a new stream should have been opened"

    engine.activate()
    engine.audio.push(speech(1.0), silence(1.8))
    assert engine.events.expect("transcription")["text"] == "hello world"


def test_healthy_stream_is_never_declared_lost(engine):
    """A14b — the watchdog must not fire while audio is flowing.

    A false positive would drop the user out of dictation for no reason, so this
    holds a stream open well past the timeout with nothing but silence.
    """
    engine.activate()
    for _ in range(int((AUDIO_TIMEOUT + 1.5) / 0.4)):
        engine.audio.push(silence(0.4))
        time.sleep(0.4)

    engine.events.expect_not("warning", "idle", within=0.5)
