"""A11–A13 — language selection and the constraint on detection."""

from .harness import silence, speech


def _dictate_once(engine):
    engine.activate()
    engine.audio.push(speech(1.0), silence(1.8))
    return engine.events.expect("transcription")


def test_single_language_skips_detection(engine_factory):
    """A11 — with one language configured, detect_language is never called."""
    engine = engine_factory(languages="pl").wait_until_idle()
    _dictate_once(engine)

    assert engine.whisper.calls("detect_language") == []
    assert engine.whisper.calls("transcribe")[0]["language"] == "pl"


def test_multiple_languages_run_detection(engine_factory):
    """A12 — with several configured, detection runs before transcription."""
    engine = engine_factory(languages="en,pl").wait_until_idle()
    _dictate_once(engine)

    assert len(engine.whisper.calls("detect_language")) == 1


def test_detection_is_constrained_to_the_selected_set(engine_factory):
    """A12 — a language the user did not select can never win.

    Whisper is confident the audio is German; German is not in the configured
    set, so the engine must still pick the best of English and Polish.
    """
    engine = engine_factory(languages="en,pl").wait_until_idle()
    engine.whisper.probs = {"de": 0.95, "en": 0.03, "pl": 0.01}

    _dictate_once(engine)

    transcribe = engine.whisper.calls("transcribe")[0]
    assert transcribe["language"] == "en"
    assert transcribe["language"] != "de"


def test_detection_picks_the_most_likely_selected_language(engine_factory):
    """A13 — among the configured languages, the highest score wins."""
    engine = engine_factory(languages="en,pl").wait_until_idle()
    engine.whisper.probs = {"pl": 0.8, "en": 0.1, "de": 0.05}

    event = _dictate_once(engine)
    assert engine.whisper.calls("transcribe")[0]["language"] == "pl"
    assert event["text"] == "hello world"


def test_detected_language_is_reported(engine_factory):
    """A13 — the chosen language is announced to the host."""
    engine = engine_factory(languages="en,pl").wait_until_idle()
    engine.whisper.probs = {"pl": 0.8, "en": 0.1}

    engine.activate()
    engine.audio.push(speech(1.0), silence(1.8))

    event = engine.events.expect("language_detected")
    assert event["language"] == "pl"


def test_empty_transcription_reports_nothing(engine):
    """A5/A18 — a blank result produces neither event.

    The host has a `transcription_empty` case that nothing sends; this pins down
    what actually happens instead.
    """
    engine.whisper.text = ""
    engine.activate()
    engine.audio.push(speech(1.0), silence(1.8))

    engine.events.expect("transcribing")
    engine.events.expect_not("transcription", "language_detected", within=1.0)
