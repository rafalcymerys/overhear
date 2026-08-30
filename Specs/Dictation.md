# Dictation

The core loop: activating dictation, speaking in batches, and having text
arrive in the focused application.

## Transcribes one utterance into the focused field

1. Open Overhear and wait for it to finish loading.
2. Open TextEdit and place the cursor in an empty document.
3. Click the menu bar icon and choose **Start Listening**.
4. Say `hello-en`.
5. Stop speaking and wait two seconds.

Assert: the text appears in the TextEdit document.
Assert: the text matches what was said, allowing for punctuation and casing.
Assert: nothing is inserted before the pause ends.
Assert: dictation stays active afterwards, ready for the next utterance.

## Transcribes several utterances in a row

1. Start dictation with TextEdit focused.
2. Say `hello-en`, pause two seconds.
3. Say `sentence-en`, pause two seconds.
4. Say `paragraph-en`, pause two seconds.

Assert: three separate insertions arrive, in the order spoken.
Assert: each insertion arrives after its own pause rather than all at the end.
Assert: no utterance is merged with the next.

## Keeps recording through a long utterance

1. Start dictation with TextEdit focused.
2. Say `paragraph-en` without pausing for more than a second at any point.

Assert: the whole paragraph arrives as a single insertion.
Assert: no part of it is dropped mid-sentence.

## Splits speech longer than the batch cap

1. Start dictation with TextEdit focused.
2. Say `monologue-en`, speaking continuously past 35 seconds.

Assert: text arrives before the user stops speaking.
Assert: the first batch covers approximately the first 30 seconds.
Assert: speech after the cap is transcribed in a following batch rather than
being discarded.

## Ignores silence

1. Start dictation with TextEdit focused.
2. Say `silence`.
3. Wait ten seconds.

Assert: nothing is inserted into the document.
Assert: no entry is added to **Last Transcriptions**.
Assert: dictation stays active.

## Ignores background noise with no speech

1. Start dictation with TextEdit focused.
2. Play `background-noise` for ten seconds without speaking.

Assert: nothing is inserted into the document.
Assert: dictation stays active.

## Ignores speech below the level threshold

1. Start dictation with TextEdit focused.
2. Say `quiet-en`.
3. Wait three seconds.

Assert: nothing is inserted into the document.
Assert: speaking `hello-en` at a normal volume immediately afterwards is
transcribed as usual.

## Stopping discards an utterance in progress

1. Start dictation with TextEdit focused.
2. Begin saying `paragraph-en`.
3. While still speaking, click **Stop Listening** in the menu bar menu.

Assert: nothing is inserted into the document.
Assert: no entry is added to **Last Transcriptions**.
Assert: the menu bar icon returns to the idle state.

## Stopping discards a transcription already running

1. Start dictation with TextEdit focused.
2. Say `sentence-en` and stop speaking.
3. As soon as the transcribing state appears, click **Stop Listening**.

Assert: nothing is inserted into the document.
Assert: no entry is added to **Last Transcriptions**.

## Restarting dictation after stopping

1. Start dictation, say `hello-en`, and let it paste.
2. Choose **Stop Listening**.
3. Choose **Start Listening** again.
4. Say `sentence-en`.

Assert: the second utterance is transcribed and inserted.
Assert: the earlier transcription is still listed under **Last Transcriptions**.

## Text arrives in whichever application is focused

1. Start dictation.
2. Focus TextEdit and say `hello-en`, then wait for the insertion.
3. Focus a different application with a text field, such as a browser address
   bar or Notes.
4. Say `sentence-en` and wait for the insertion.

Assert: each insertion lands in the application focused at the time.
Assert: no text is inserted into Overhear's own windows.

## Preserves the clipboard

1. Copy a distinctive string to the clipboard.
2. Start dictation with TextEdit focused.
3. Say `hello-en` and wait for the insertion.
4. Wait one second, then paste with Cmd+V.

Assert: the pasted content is the string copied in step 1.
Assert: the transcription is in the document from step 3, not from the paste.

## Dictating while the settings window is open

1. Start dictation.
2. Open **Settings…** from the menu bar menu and leave it focused.
3. Say `hello-en`.

Assert: dictation continues while the settings window is open.
Assert: the transcription is added to **Last Transcriptions**.
