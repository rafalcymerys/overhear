# Cancel Word

Saying the cancel word during dictation discards whatever is currently being
heard or transcribed, and dictation continues.

## Cancels an utterance in progress

1. Start dictation with TextEdit focused.
2. Begin saying `paragraph-en`.
3. While still speaking, say `alexa`.

Assert: nothing is inserted into the document.
Assert: no entry is added to **Last Transcriptions**.
Assert: the menu bar icon and the overlay both show the cancelled state in red
for about a second.
Assert: dictation returns to the ready state and stays active.
Assert: saying `hello-en` afterwards is transcribed normally.

## Cancels at the end of an utterance

1. Start dictation with TextEdit focused.
2. Say `sentence-then-alexa` as one continuous utterance.

Assert: nothing is inserted into the document.
Assert: the cancelled state is shown.

## Cancels while transcription is running

1. Start dictation with TextEdit focused.
2. Say `alexa-during-transcription`: speak `sentence-en`, pause so the
   transcribing state appears, then say "Alexa" within one second.

Assert: nothing is inserted into the document.
Assert: no entry is added to **Last Transcriptions**.
Assert: the cancelled state is shown.

## Does not lose the next utterance after cancelling

1. Start dictation with TextEdit focused.
2. Say `sentence-en`, pause until the transcribing state appears, then say
   "Alexa" followed immediately by `hello-en`.

Assert: the cancelled batch is not inserted.
Assert: `hello-en` is transcribed and inserted, with its opening word intact.

## Does not fire on ordinary speech

1. Start dictation with TextEdit focused.
2. Say `paragraph-en`, which contains no cancel word.
3. Say `sentence-pl` with Polish selected.

Assert: neither utterance triggers the cancelled state.
Assert: both are inserted.

## Cancel word is inert while dictation is stopped

1. Ensure dictation is stopped.
2. Say `alexa`.

Assert: nothing happens.
Assert: the menu bar icon stays in the idle state.
Assert: no cancelled state is shown.

## Switching the cancel word

1. Open **Settings… → Hot Words**.
2. Change **Cancel word** from Alexa to Hey Jarvis.
3. Wait for the engine to reload.
4. Start dictation and say `hey-jarvis` while speaking.
5. Say `alexa` while speaking a second utterance.

Assert: `hey-jarvis` cancels the batch.
Assert: `alexa` no longer cancels, and the utterance containing it is
transcribed.

## Changing the cancel word during dictation stops it [to review]

1. Start dictation and confirm the active state in the menu bar.
2. Open **Settings… → Hot Words** and change **Cancel word**.
3. Wait two seconds and look at the menu bar icon.

Assert: dictation is still active after the change, or the user is told it
stopped.

Changing the cancel word rebuilds the engine, which returns to idle. Dictation
does not resume, and nothing indicates that it stopped other than the menu bar
icon reverting. The same happens when changing the language selection.

## Repeated cancel words

1. Start dictation with TextEdit focused.
2. Say `alexa` three times in a row with short pauses.

Assert: each utterance is discarded.
Assert: nothing is inserted into the document.
Assert: dictation remains active throughout.
