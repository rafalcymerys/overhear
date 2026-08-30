"""Builds the samples that are not plain speech.

Run from generate.sh, after the `say` output exists. Everything reads and
writes 16 kHz mono 16-bit WAV.
"""

import array
import math
import random
import struct
import wave

RATE = 16000


def read(path):
    with wave.open(path) as w:
        assert w.getframerate() == RATE, f"{path} is not {RATE} Hz"
        assert w.getnchannels() == 1, f"{path} is not mono"
        return array.array("h", w.readframes(w.getnframes()))


def write(path, samples):
    clipped = array.array("h", (max(-32768, min(32767, int(s))) for s in samples))
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(clipped.tobytes())


def silence(seconds):
    return array.array("h", [0] * int(RATE * seconds))


# The user says nothing for five seconds. Digital silence rather than room
# tone: the engine's own threshold is what these specs exercise.
write("silence.wav", silence(5.0))


# A cough: a sharp burst of band-limited noise with a fast attack and a short
# decay, twice, the way a real one usually arrives.
def cough_burst(duration, amplitude, seed):
    rng = random.Random(seed)
    samples = []
    count = int(RATE * duration)
    previous = 0.0
    for i in range(count):
        position = i / count
        # Fast attack, exponential decay.
        envelope = (position / 0.06) if position < 0.06 else math.exp(-6.0 * (position - 0.06))
        # One-pole low pass over white noise, so it sits in the chest register
        # rather than sounding like a hiss.
        noise = rng.uniform(-1.0, 1.0)
        previous = previous + 0.35 * (noise - previous)
        samples.append(previous * envelope * amplitude)
    return samples


cough = []
cough.extend(silence(0.25))
cough.extend(cough_burst(0.45, 22000, seed=1))
cough.extend(silence(0.30))
cough.extend(cough_burst(0.38, 17000, seed=2))
cough.extend(silence(0.60))
write("coughing.wav", cough)


# Background noise with no speech in it: a low hum plus intermittent clicks,
# standing in for a room with a fan and someone typing.
rng = random.Random(7)
noise = []
click_at = set()
position = 0.0
while position < 8.0:
    position += rng.uniform(0.08, 0.45)
    click_at.add(int(position * RATE))

previous = 0.0
for i in range(int(RATE * 8.0)):
    hum = 900 * math.sin(2 * math.pi * 60 * i / RATE)
    previous = previous + 0.05 * (rng.uniform(-1.0, 1.0) - previous)
    value = hum + previous * 1400
    # Keystroke transients.
    for start in (i - 0, i - 1, i - 2):
        if start in click_at:
            value += rng.uniform(-9000, 9000) * math.exp(-40.0 * (i - start) / RATE)
    noise.append(value)
write("background-noise.wav", noise)


# Whispered speech: the sample is defined by being too quiet to cross the
# engine's level threshold, so the amplitude is what matters, not the timbre.
write("quiet-en.wav", [s * 0.012 for s in read("_quiet-source.wav")])


# One utterance that switches language mid-sentence, assembled from the two
# voices with no gap between them.
mixed = []
for part in ("_mixed-a.wav", "_mixed-b.wav", "_mixed-c.wav"):
    mixed.extend(read(part))
write("mixed-en-pl.wav", mixed)


# A sentence, a pause long enough for transcription to start, then the cancel
# word. The engine ends a batch after 1.5s of silence, so the gap sits under
# that and the cancel word lands while Whisper is still running.
during = []
during.extend(read("sentence-en.wav"))
during.extend(silence(1.2))
during.extend(read("alexa.wav"))
write("alexa-during-transcription.wav", during)
