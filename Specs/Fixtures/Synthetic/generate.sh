#!/bin/bash
# Regenerates the synthetic recordings for the samples in ../AudioSamples.md.
#
# Everything is 16 kHz mono 16-bit WAV, the format the engine consumes, so a
# sample can be fed to the transcriber directly as well as played at a
# microphone.
#
# Speech comes from macOS `say`. The samples that are not speech — silence,
# coughing, background noise — are synthesised, and the ones describing a
# sequence of events are assembled from the parts.
set -euo pipefail

cd "$(dirname "$0")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

EN=Samantha
PL=Zosia
DE=Anna
FR=Thomas

# say → 16 kHz mono WAV
speak() {
    local name="$1" voice="$2" text="$3"
    say -v "$voice" -o "$WORK/$name.aiff" "$text"
    afconvert -f WAVE -d LEI16@16000 -c 1 "$WORK/$name.aiff" "$name.wav"
}

speak HelloEn "$EN" "Hello."
speak SentenceEn "$EN" "The quick brown fox jumps over the lazy dog."
speak ParagraphEn "$EN" "I am writing a long message to test how the application handles speech that runs on for a while. It should keep listening for as long as I keep talking, and it should not cut me off in the middle of a sentence just because I have been speaking for some time."
speak MonologueEn "$EN" "I am going to keep talking for quite a long time now, without stopping, so that the recording runs past the point where a single batch of speech is supposed to end. The application caps a batch at thirty seconds, and I want to be sure that what I say after that point is still transcribed rather than quietly thrown away. So I will keep going, describing nothing in particular, filling the time with ordinary sentences that carry no special meaning at all. The weather this morning was unremarkable. The coffee was too hot to drink for the first few minutes. There is a stack of books on the desk that I have been meaning to read for months, and every week I move it slightly to the left and then forget about it again. None of this matters, and that is rather the point, because what I need from this recording is length rather than content. I am still talking. I will keep talking until well past the cap, and then I will say one final sentence so that it is obvious where the end is. This is the final sentence."
speak DzienDobryPl "$PL" "Dzień dobry."
speak SentencePl "$PL" "Dzień dobry, to jest test rozpoznawania mowy po polsku."
speak ParagraphPl "$PL" "Piszę dłuższą wiadomość, żeby sprawdzić jak aplikacja radzi sobie z dłuższą wypowiedzią po polsku. Powinna nagrywać tak długo, jak długo mówię, i nie powinna mi przerywać w środku zdania."
speak GutenTagDe "$DE" "Guten Tag, das ist ein Test der Spracherkennung auf Deutsch."
speak BonjourFr "$FR" "Bonjour, ceci est un test de reconnaissance vocale en français."
speak Alexa "$EN" "Alexa."
speak HeyJarvis "$EN" "Hey Jarvis."
speak SentenceThenAlexa "$EN" "The quick brown fox jumps over, Alexa."

# Parts used only to build composite samples.
speak _mixed-a "$EN" "Hello,"
speak _mixed-b "$PL" "dzień dobry,"
speak _mixed-c "$EN" "this is a test."
speak _quiet-source "$EN" "Hello."

python3 compose.py
rm -f _mixed-a.wav _mixed-b.wav _mixed-c.wav _quiet-source.wav

echo
for f in *.wav; do
    printf '%-28s %5.1fs\n' "$f" "$(python3 -c "
import wave, sys
with wave.open('$f') as w:
    print(w.getnframes() / w.getframerate())
")"
done
