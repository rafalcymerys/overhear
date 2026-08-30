# Transcription Output

What reaches the document after a batch is transcribed: annotation filtering,
and the pasteboard mechanics of the insertion itself.

## Drops non-speech annotations

1. Open **Settings… → General** and confirm **Strip transcription annotations**
   is on.
2. Start dictation with TextEdit focused.
3. Say `Coughing`.
4. Wait three seconds.

Assert: nothing is inserted into the document.
Assert: no entry is added to **Last Transcriptions**.
Assert: dictation stays active.

## Keeps speech that arrives alongside an annotation

1. Confirm **Strip transcription annotations** is on.
2. Start dictation with TextEdit focused.
3. Cough, then immediately say `SentenceEn` without pausing between them.

Assert: the spoken sentence is inserted.
Assert: the inserted text contains no bracketed or parenthesised description
such as `(coughing)` or `[ Pause ]`.

## Passes annotations through when the setting is off

1. Open **Settings… → General** and turn **Strip transcription annotations**
   off.
2. Start dictation with TextEdit focused.
3. Say `Coughing`.

Assert: whatever the model produces is inserted, including any parenthesised
description.
Assert: toggling the setting takes effect on the next utterance without an
engine reload.

## Square bracket annotations are always dropped

1. Turn **Strip transcription annotations** off.
2. Start dictation with TextEdit focused.
3. Say `Silence` for several seconds, then `BackgroundNoise`.

Assert: no inserted text contains `[ Pause ]`, `[BLANK_AUDIO]` or any other
square-bracketed description, with the setting off.

## Leaves ordinary punctuation alone

1. Confirm **Strip transcription annotations** is on.
2. Start dictation with TextEdit focused.
3. Say `ParagraphEn`.

Assert: the inserted text keeps its commas, full stops and casing.
Assert: no words are removed.

## Restores the clipboard after inserting

1. Copy a distinctive string to the clipboard.
2. Start dictation with TextEdit focused.
3. Say `HelloEn` and wait for the insertion.
4. Wait one second, then press Cmd+V.

Assert: the pasted content is the string from step 1.
Assert: the clipboard is restored within about a second of the insertion.

## Two insertions in quick succession corrupt the clipboard [to review]

1. Copy a distinctive string to the clipboard.
2. Dictate two short utterances so that both appear under
   **Last Transcriptions**.
3. Open the menu bar menu and click one transcription.
4. Reopen the menu immediately and click the other, within half a second of the
   first.
5. Wait two seconds and press Cmd+V.

Assert: the pasted content is the string from step 1.

The second insertion begins before the first has restored the clipboard, and
reads the first transcription as the content to restore. The original clipboard
is replaced by a transcription.

## Inserts text containing non-Latin characters

1. Select Polish.
2. Start dictation with TextEdit focused.
3. Say `SentencePl`.

Assert: Polish diacritics are inserted correctly.
Assert: no characters are replaced by escapes or question marks.

## Inserts into an application that does not accept paste

1. Start dictation.
2. Focus an application with no editable text field, such as the Finder desktop.
3. Say `HelloEn`.

Assert: the app does not crash or hang.
Assert: the transcription is added to **Last Transcriptions**.
Assert: dictation stays active.
