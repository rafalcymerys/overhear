# Dictation

The core loop: activating dictation, speaking in batches, and having text
arrive in the focused application.

Every scenario is in the default **Always-on listening** mode unless it
says otherwise — hold to talk names itself in the step that sets it up, here
and in every other spec.

## Transcribes one utterance into the focused field

1. Open Overhear and wait for it to finish loading.
2. Open TextEdit and place the cursor in an empty document.
3. Click the menu bar icon and choose **Start Listening**.
4. Say `HelloEn`.
5. Stop speaking and wait two seconds.

Assert: the text appears in the TextEdit document.
Assert: the text matches what was said, allowing for punctuation and casing.
Assert: nothing is inserted before the pause ends.
Assert: dictation stays active afterwards, ready for the next utterance.

## Transcribes several utterances in a row

1. Start dictation with TextEdit focused.
2. Say `HelloEn`, pause two seconds.
3. Say `SentenceEn`, pause two seconds.
4. Say `ParagraphEn`, pause two seconds.

Assert: three separate insertions arrive, in the order spoken.
Assert: each insertion arrives after its own pause rather than all at the end.
Assert: no utterance is merged with the next.

## Keeps recording through a long utterance

1. Start dictation with TextEdit focused.
2. Say `ParagraphEn` without pausing for more than a second at any point.

Assert: the whole paragraph arrives as a single insertion.
Assert: no part of it is dropped mid-sentence.

## Splits speech longer than the batch cap

1. Start dictation with TextEdit focused.
2. Say `MonologueEn`, speaking continuously past 35 seconds.

Assert: text arrives before the user stops speaking.
Assert: the first batch covers approximately the first 30 seconds.
Assert: speech after the cap is transcribed in a following batch rather than
being discarded.

## Ignores silence

1. Start dictation with TextEdit focused.
2. Say `Silence`.
3. Wait ten seconds.

Assert: nothing is inserted into the document.
Assert: no entry is added to **Last Transcriptions**.
Assert: dictation stays active.

## Ignores background noise with no speech

1. Start dictation with TextEdit focused.
2. Play `BackgroundNoise` for ten seconds without speaking.

Assert: nothing is inserted into the document.
Assert: dictation stays active.

## Ignores speech below the level threshold

1. Start dictation with TextEdit focused.
2. Say `QuietEn`.
3. Wait three seconds.

Assert: nothing is inserted into the document.
Assert: speaking `HelloEn` at a normal volume immediately afterwards is
transcribed as usual.

## Stopping discards an utterance in progress

1. Start dictation with TextEdit focused.
2. Begin saying `ParagraphEn`.
3. While still speaking, click **Stop Listening** in the menu bar menu.

Assert: nothing is inserted into the document.
Assert: no entry is added to **Last Transcriptions**.
Assert: the menu bar icon returns to the idle state.

## Stopping discards a transcription already running

1. Start dictation with TextEdit focused.
2. Say `SentenceEn` and stop speaking.
3. As soon as the transcribing state appears, click **Stop Listening**.

Assert: nothing is inserted into the document.
Assert: no entry is added to **Last Transcriptions**.

## Restarting dictation after stopping

1. Start dictation, say `HelloEn`, and let it paste.
2. Choose **Stop Listening**.
3. Choose **Start Listening** again.
4. Say `SentenceEn`.

Assert: the second utterance is transcribed and inserted.
Assert: the earlier transcription is still listed under **Last Transcriptions**.

## Starting and stopping with the global hotkey

1. Record ⌃⌥D as the listening hotkey in **Settings… → General**, with
   **Always-on listening** chosen.
2. Close Overhear's windows and focus TextEdit.
3. Press ⌃⌥D.
4. Say `HelloEn` and wait for the insertion.
5. Press ⌃⌥D again.

Assert: the first press starts dictation, and the menu bar icon and overlay
show it, without Overhear taking focus.
Assert: the transcription lands in TextEdit.
Assert: the second press stops dictation, as **Stop Listening** would.
Assert: holding the combination down is one toggle, not a repeating one.

## The hotkey does not reach the focused application

1. With ⌃⌥D recorded and **Always-on listening** chosen, place the cursor
   in a TextEdit document.
2. Press ⌃⌥D twice.

Assert: nothing is typed into the document.
Assert: TextEdit gives no sign of the keystroke, such as an alert beep.

## The hotkey works while Overhear's own windows are open

1. With ⌃⌥D recorded and **Always-on listening** chosen, open
   **Settings…** and leave it focused.
2. Press the hotkey.
3. Press it again while the overlay is showing.

Assert: dictation starts and stops as it does from any other app.
Assert: the settings window keeps focus and its controls are unaffected.

## Holding the hotkey dictates for as long as it is held

1. Record ⌃⌥D in **Settings… → General** and choose **Hold to talk**.
2. Focus TextEdit.
3. Hold ⌃⌥D down, say `SentenceEn`, and release it as the sentence ends.

Assert: dictation starts on the press, and the menu bar icon and overlay show
it, without Overhear taking focus.
Assert: the release ends the batch rather than discarding it — what was said
up to the release is transcribed and inserted, which is where hold to talk
parts company with **Stop Listening**.
Assert: dictation is not active once the insertion has arrived; the icon
returns to idle and the menu says **Hold ⌃⌥D to talk**, as it did before the
hold.
Assert: holding the combination for several seconds is one session, not a
repeating toggle.

## Speaking across several holds

1. With ⌃⌥D recorded and **Hold to talk** chosen, focus TextEdit.
2. Hold the hotkey, say `HelloEn`, release.
3. Hold it again, say `SentenceEn`, release.

Assert: two separate insertions arrive, in the order spoken.
Assert: neither hold is merged with the next.
Assert: both are listed under **Last Transcriptions**.

## A tap with no speech in it

1. With ⌃⌥D recorded and **Hold to talk** chosen, focus TextEdit.
2. Press and release the hotkey without saying anything.

Assert: nothing is inserted into the document.
Assert: no entry is added to **Last Transcriptions**.
Assert: the menu is unchanged — a stray tap leaves nothing running.

There is no minimum hold. A tap is a session with silence in it, and silence
already produces nothing.

## Releasing while a transcription is already running

1. With ⌃⌥D recorded and **Hold to talk** chosen, hold the hotkey, say
   `HelloEn`, and release.
2. As soon as the transcribing state appears, press and release the hotkey
   again without speaking.

Assert: the first utterance still arrives.
Assert: the second press does not cancel it.

## Holding across an application switch

1. With ⌃⌥D recorded and **Hold to talk** chosen, focus TextEdit.
2. Hold the hotkey and say `HelloEn`.
3. Still holding, click into another application with a text field.
4. Say `SentenceEn` and release.

Assert: dictation continues across the switch rather than ending with the
focus change.
Assert: each insertion lands in the application focused at the time.

## The key never comes back up

1. With ⌃⌥D recorded and **Hold to talk** chosen, hold the hotkey and say
   `SentenceEn`.
2. While still holding, lock the screen.

Assert: dictation ends rather than staying active with nobody holding a key.
Assert: the icon returns to idle and the menu says **Hold ⌃⌥D to talk**.
Assert: the hotkey works as usual on the next press.

## A held modifier types nothing in the application underneath

1. Record Right Option as the hotkey and choose **Hold to talk**.
2. Place the cursor in a TextEdit document.
3. Hold Right Option for several seconds, say `HelloEn`, and release.

Assert: nothing is typed into the document beyond the transcription.
Assert: TextEdit gives no sign of the keystroke, such as an alert beep.
Assert: the application does not behave as though the modifier were still down
after the release.

## The menu offers no way to start listening in hold to talk

1. With ⌃⌥D recorded and **Hold to talk** chosen, ensure dictation is stopped.
2. Click the menu bar icon.

Assert: neither **Start Listening** nor **Stop Listening** appears — the key
is the only way in, and an item that started dictation from the mouse would
leave nothing to release.
Assert: in their place the menu says **Hold ⌃⌥D to talk**, which is not an
action and cannot be clicked, the way **Loading the model…** is not —
`Specs/StatusDisplay.md`.
Assert: the rest of the menu is unchanged.
Assert: choosing **Always-on listening** brings **Start Listening** back,
with its combination against its right edge.

## Hold to talk with no hotkey recorded

1. Choose **Hold to talk** in **Settings… → General** with no combination
   recorded.
2. Close settings and click the menu bar icon.

Assert: **Set a Listening Hotkey…** takes the place **Start Listening** would,
and opens **Settings… → General** — an item that leads somewhere, the way
**Finish Setup…** does.
Assert: no other route starts dictation — this mode has no key to hold, and
the menu offers no toggle.
Assert: recording a combination replaces it with **Hold ⌃⌥D to talk**.

The mode is offered whether or not a combination is recorded, so this state is
reachable, and the menu is where the user finds out —
`Specs/Settings.md`.

## The menu while the hotkey is held

1. Record Right Option and choose **Hold to talk**.
2. Hold it, begin saying `ParagraphEn`, and click the menu bar icon while
   still holding.

Assert: the menu still says **Hold ⌥ to talk** and offers no **Stop
Listening** — there is nothing to press that the release does not already do.
Assert: releasing the key with the menu open ends the session and inserts what
was said.

## Stopping from the overlay during a hold

1. Record Right Option, choose **Hold to talk**, and confirm the overlay is
   shown.
2. Hold the key and begin saying `ParagraphEn`.
3. Still holding, click the stop button on the overlay.

Assert: nothing is inserted into the document — stopping discards, whichever
mode it happens in.
Assert: the overlay disappears and the icon returns to idle.
Assert: releasing the key afterwards does nothing and does not start a new
session.

## Switching to hold to talk while dictating stops it

1. With ⌃⌥D recorded and **Always-on listening** chosen, start dictation with
   the hotkey.
2. Say `HelloEn` and let it arrive, then begin saying `ParagraphEn`.
3. While still speaking, open **Settings… → General** and choose
   **Hold to talk**.

Assert: dictation stops of its own accord, as **Stop Listening** would — the
session belonged to the mode that has just been replaced.
Assert: the utterance in progress is discarded: nothing of `ParagraphEn` is
inserted, and no entry is added to **Last Transcriptions** for it.
Assert: the transcription from step 2 is still listed, and still in the
document.
Assert: the menu bar icon returns to idle, the overlay disappears, and the menu
says **Hold ⌃⌥D to talk**.
Assert: no engine reload happens — the mode is not one of the settings the
engine is built from.
Assert: the next hold starts and ends a session in the new mode.

Left running, the session would be one no key could end: the release ends only
what a hold started, and hold to talk offers no **Stop Listening** to reach it
with — `Specs/StatusDisplay.md`.

Changing the mode ends whatever is running, whichever way it is changed —
below.

## Switching to always-on listening mid-hold stops it too

1. With Right Option recorded and **Hold to talk** chosen, hold it and begin
   saying `ParagraphEn`.
2. Still holding, open **Settings… → General** and choose **Always-on
   listening**.
3. Let go of the key.

Assert: dictation stops as the switch is made, without waiting for the key to
come up.
Assert: the utterance in progress is discarded — nothing of `ParagraphEn` is
inserted, and no entry is added to **Last Transcriptions** for it.
Assert: the menu bar icon returns to idle, the overlay disappears, and the menu
offers **Start Listening**.
Assert: letting go does nothing: it does not transcribe what was said before
the switch, and it does not start a session in the new mode.
Assert: pressing the combination afterwards starts one, as a press does in this
mode.

The session belonged to the mode it was started in. Ending it either way is
one rule rather than two, and it leaves nothing running that the mode the user
has just chosen would not have started.

## The hotkey does nothing while the engine is not ready

1. Launch Overhear with the models still downloading, or with the engine in
   its error state.
2. Press the hotkey, and hold it for a few seconds, in each mode.

Assert: dictation does not start in either mode.
Assert: the menu bar icon does not change.
Assert: the hotkey works as usual once the engine reaches idle.

## Text arrives in whichever application is focused

1. Start dictation.
2. Focus TextEdit and say `HelloEn`, then wait for the insertion.
3. Focus a different application with a text field, such as a browser address
   bar or Notes.
4. Say `SentenceEn` and wait for the insertion.

Assert: each insertion lands in the application focused at the time.
Assert: no text is inserted into Overhear's own windows.

## Preserves the clipboard

1. Copy a distinctive string to the clipboard.
2. Start dictation with TextEdit focused.
3. Say `HelloEn` and wait for the insertion.
4. Wait one second, then paste with Cmd+V.

Assert: the pasted content is the string copied in step 1.
Assert: the transcription is in the document from step 3, not from the paste.

## Dictating while the settings window is open

1. Start dictation.
2. Open **Settings…** from the menu bar menu and leave it focused.
3. Say `HelloEn`.

Assert: dictation continues while the settings window is open.
Assert: the transcription is added to **Last Transcriptions**.
