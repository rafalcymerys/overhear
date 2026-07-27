"""The real-model lane: same fake microphone, but genuine openwakeword and
faster-whisper.

Everything else stubs the ML libraries so that event sequencing can be asserted
deterministically. These few tests exist to prove the wiring to the real
libraries is correct — that the models load, that audio in the engine's format
is actually transcribable, and that argument plumbing matches what the libraries
expect. They are skipped unless --run-slow is passed.

Speech is generated with macOS `say` rather than checked-in WAVs, so there is
nothing binary in the repo and the fixtures regenerate anywhere with a Mac.
"""

import shutil
import subprocess
import wave

import numpy as np
import pytest

from .constants import CHUNK_SAMPLES, SAMPLE_RATE
from .harness import silence

pytestmark = [
    pytest.mark.slow,
    pytest.mark.skipif(shutil.which("say") is None or shutil.which("afconvert") is None,
                       reason="needs macOS `say` and `afconvert`"),
]

MODEL_LOAD_TIMEOUT = 180.0
TRANSCRIBE_TIMEOUT = 120.0


def _installed_voices():
    listing = subprocess.run(["say", "-v", "?"], capture_output=True, text=True).stdout
    return {line.split()[0] for line in listing.splitlines() if line.strip()}


def _require_voice(name):
    """Skip rather than error when a CI runner lacks a localized voice."""
    if name not in _installed_voices():
        pytest.skip("system voice %r is not installed" % name)


def _pad_to_chunk(samples):
    remainder = len(samples) % CHUNK_SAMPLES
    if remainder:
        samples = np.concatenate([samples, np.zeros(CHUNK_SAMPLES - remainder, dtype=np.float32)])
    return samples


@pytest.fixture(scope="session")
def tts(tmp_path_factory):
    """Render text to 16kHz mono float32 via the system speech synthesizer."""
    cache = {}
    outdir = tmp_path_factory.mktemp("tts")

    def render(text, voice="Samantha", rate=170):
        key = (text, voice, rate)
        if key in cache:
            return cache[key]
        aiff = outdir / "clip.aiff"
        wav = outdir / "clip.wav"
        subprocess.run(["say", "-v", voice, "-r", str(rate), "-o", str(aiff), text],
                       check=True, capture_output=True)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@%d" % SAMPLE_RATE,
                        "-c", "1", str(aiff), str(wav)],
                       check=True, capture_output=True)
        with wave.open(str(wav)) as handle:
            frames = handle.readframes(handle.getnframes())
        samples = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0
        cache[key] = _pad_to_chunk(samples)
        return cache[key]

    return render


@pytest.fixture(scope="session")
def real_engine_factory():
    from .harness import Engine

    built = []

    def build(languages="en", cancel_word="hey_jarvis"):
        engine = Engine(languages=languages, cancel_word=cancel_word, stub_models=False)
        built.append(engine)
        engine.start()
        engine.wait_until_idle(timeout=MODEL_LOAD_TIMEOUT)
        return engine

    yield build

    for engine in built:
        engine.close()


def test_real_models_load(real_engine_factory):
    """The real libraries load with the arguments the engine passes them."""
    engine = real_engine_factory()
    assert engine.process.poll() is None


def test_real_transcription_round_trip(real_engine_factory, tts):
    """Synthesized speech makes it all the way to a transcription event.

    Asserted loosely — this is a wiring test, not a measure of Whisper accuracy.
    """
    engine = real_engine_factory()
    engine.activate()
    engine.audio.push(tts("The quick brown fox jumps over the lazy dog."), silence(2.0))

    engine.events.expect("speech_start", timeout=TRANSCRIBE_TIMEOUT)
    event = engine.events.expect("transcription", timeout=TRANSCRIBE_TIMEOUT)

    text = event["text"].lower()
    assert text.strip()
    assert "fox" in text or "quick" in text

    # ordinary speech must not read as the cancel word
    engine.events.expect_not("wake_word_cancel", within=1.0)


def test_real_language_detection_runs_for_multiple_languages(real_engine_factory, tts):
    """The multi-language path works against the real faster-whisper API.

    This is the configuration every default install runs — AppSettings ships with
    English and Polish selected — and it is the only path that calls
    detect_language(). Without this test the engine's unpacking of
    `(language, probability, all_language_probs)` is asserted only against the
    fake, so a change to that return shape would break the default setup with a
    green suite.
    """
    engine = real_engine_factory(languages="en,pl")
    engine.activate()
    engine.audio.push(tts("The quick brown fox jumps over the lazy dog."), silence(2.0))

    detected = engine.events.expect("language_detected", timeout=TRANSCRIBE_TIMEOUT)
    assert detected["language"] == "en"


def test_real_detection_distinguishes_the_selected_languages(real_engine_factory, tts):
    """Polish speech is detected as Polish, not just defaulted to the first entry."""
    _require_voice("Zosia")

    engine = real_engine_factory(languages="en,pl")
    engine.activate()
    engine.audio.push(
        tts("Dzień dobry, nazywam się Zosia i mówię po polsku.", voice="Zosia"),
        silence(2.0),
    )

    detected = engine.events.expect("language_detected", timeout=TRANSCRIBE_TIMEOUT)
    assert detected["language"] == "pl"


def test_real_detection_is_constrained_to_the_selected_set(real_engine_factory, tts):
    """A language the user did not select cannot win, against the real model.

    The fast lane asserts this against a fake probability map; here Whisper
    genuinely believes the audio is German, and the engine must still narrow its
    real all_language_probs list down to the configured set.
    """
    _require_voice("Anna")

    engine = real_engine_factory(languages="en,pl")
    engine.activate()
    engine.audio.push(
        tts("Der schnelle braune Fuchs springt über den faulen Hund.", voice="Anna"),
        silence(2.0),
    )

    detected = engine.events.expect("language_detected", timeout=TRANSCRIBE_TIMEOUT)
    assert detected["language"] in {"en", "pl"}


def test_real_cancel_word_is_detected(real_engine_factory, tts):
    """The real wake word model fires on an actual spoken cancel word.

    The stubbed lane triggers cancels with a sentinel sample value, which proves
    the engine's plumbing but says nothing about detection itself. This closes
    that gap: real audio, real ONNX model, real 0.5 threshold.
    """
    engine = real_engine_factory()
    engine.activate()
    engine.audio.push(tts("Hey Jarvis."), silence(0.5))

    engine.events.expect("wake_word_cancel", timeout=30.0)
    engine.events.expect_not("transcription", within=2.0)
