"""A1, A2, A15–A18 — startup handshake, command handling, framing."""

import pytest

from .harness import silence, speech


def test_startup_handshake(engine_factory):
    """A1 — the engine announces itself in a fixed order and settles at idle."""
    engine = engine_factory(languages="en,pl")

    first = engine.events.expect("status")
    assert first["message"] == "loading_models"

    config = engine.events.expect("config")
    assert config["languages"] == ["en", "pl"]

    ready_messages = [
        engine.events.expect("status")["message"],
        engine.events.expect("status")["message"],
    ]
    assert ready_messages == ["wake_word_ready", "whisper_ready"]

    engine.events.expect("idle")


def test_whisper_model_configuration(engine):
    """A1 — the engine asks for the base model, int8 on CPU."""
    load = engine.whisper.calls("load")
    assert len(load) == 1
    assert load[0]["model"] == "base"
    assert load[0]["device"] == "cpu"
    assert load[0]["compute_type"] == "int8"


def test_activate_deactivate_round_trip(engine):
    """A2 — dictation can be started and stopped repeatedly."""
    for _ in range(3):
        engine.activate()
        engine.deactivate()


def test_deactivate_needs_no_audio(engine):
    """A2 — stopping works even if the microphone has gone quiet.

    record_batch re-checks the flag on every queue timeout, so this must not
    depend on another chunk arriving.
    """
    engine.activate()
    engine.send("deactivate")
    engine.events.expect("idle", timeout=3.0)


def test_malformed_commands_are_ignored(engine):
    """A15 — junk on stdin must not take the engine down."""
    engine.send_raw("this is not json")
    engine.send_raw("")
    engine.send_raw("{}")
    engine.send_raw('{"command": "bogus"}')
    engine.send_raw('{"not_a_command": "activate"}')

    engine.activate()
    assert engine.process.poll() is None


def test_quit_mid_batch_exits_cleanly(engine):
    """A16 — quitting while recording still shuts down promptly and cleanly."""
    engine.activate()
    engine.audio.push(speech(0.8))
    engine.events.expect("speech_start")

    engine.send("quit")
    assert engine.wait_exit(timeout=5.0) == 0


def test_stop_mid_utterance_discards_the_partial_batch(engine):
    """A16b — pressing Stop mid-sentence throws away what was captured.

    record_batch only returns audio when the batch finished on its own terms, so
    an utterance the user cut off never reaches their document.

    The batch has to be comfortably over dictation_loop's 0.3s floor before Stop
    arrives, otherwise it would be dropped for the wrong reason and this test
    would pass by accident. Two seconds of speech, fully consumed, puts it an
    order of magnitude clear of that edge.
    """
    engine.activate()
    engine.audio.push(speech(2.0))
    engine.events.expect("speech_start")
    engine.audio.settle()

    engine.send("deactivate")
    engine.events.expect_not("transcribing", "transcription", within=1.5)


def test_stop_during_transcription_discards_the_result(engine):
    """A16c — Stop pressed while Whisper is running suppresses the paste.

    The wider half of the same bug: transcription takes about a second, so this
    window is far easier to hit than the recording one. The batch closed
    normally here — it is the stop request that must win.
    """
    engine.whisper.manual()
    engine.activate()
    engine.audio.push(speech(1.0), silence(1.8))

    call = engine.whisper.await_call("transcribe")
    engine.events.expect("speech_start", "transcribing")

    engine.send("deactivate")
    engine.audio.settle()
    call.reply(text="text the user stopped")

    engine.events.expect_not("transcription", within=1.5)


def test_completed_batch_still_transcribes_while_dictating(engine):
    """A16c — the guard must not suppress ordinary transcriptions."""
    engine.activate()
    engine.audio.push(speech(1.0), silence(1.8))

    assert engine.events.expect("transcription")["text"] == "hello world"


def test_unknown_cancel_word_is_fatal(engine_factory):
    """A17 — a missing wake word model reports an error and exits non-zero."""
    engine = engine_factory(cancel_word="/nonexistent/model.onnx")

    error = engine.events.expect("status", "error")[1]
    assert "openwakeword" in error["message"]
    assert engine.wait_exit(timeout=5.0) == 1


@pytest.mark.parametrize("text", [
    'quotes "inside" the text',
    "emoji 🎙 and accents ąćęłńóśźż",
    "line one\nline two",
    "tab\tseparated",
    "backslash \\ and brace }",
])
def test_transcription_text_survives_the_wire(engine, text):
    """A18 — one event is always one line, whatever the transcription contains.

    ensure_ascii=False means non-Latin text travels as UTF-8; embedded newlines
    have to be escaped by json.dumps or the line framing would break.
    """
    engine.whisper.text = text
    engine.activate()
    engine.audio.push(speech(0.8), silence(1.8))

    event = engine.events.expect("transcription")
    assert event["text"] == text
