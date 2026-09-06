# Status Display

The menu bar icon, its menu, and the floating overlay.

The icon is one dot in every state. What changes is its colour and how it
moves, so the states can be told apart at a glance without any of them reading
as a different icon.

## Menu bar icon reflects the engine state

1. Open Overhear with setup complete and watch the icon through a full cycle:
   loading, idle, start dictation, speak, pause for transcription, say the
   cancel word.

Assert: loading shows the dot at full strength, pulsing.
Assert: idle shows the same dot dimmed and still.
Assert: the ready state shows the dot at full strength, still.
Assert: speaking sends a ring out from the dot, in orange.
Assert: transcribing draws a ring inward onto the dot, in orange, faster than
the one speaking sends out.
Assert: the cancel word shakes the dot in red for about a second, then returns
to the ready state.
Assert: the dot is white on a dark menu bar and black on a light one, in every
state that is not coloured.

## Setting up shows an exclamation

1. Open Overhear with a permission missing or no model downloaded.
2. Look at the menu bar icon.

Assert: the icon is a red circle with an exclamation mark through it, larger
than the dot the other states draw.
Assert: it stays that way for as long as anything setup covers is missing.
Assert: granting the last permission, or finishing the model download, replaces
it with the ordinary states without the app being restarted.
Assert: revoking a permission after setup was finished brings it back.

## A Hot Word model that will not load shows the same exclamation

1. Quit Overhear after a completed setup.
2. Truncate `melspectrogram.onnx` in
   `~/Library/Application Support/Overhear/models/` to a few bytes, so the file
   is there but will not load.
3. Open Overhear.
4. Look at the menu bar icon, then click it.

Assert: the icon shows the exclamation rather than the idle dot.
Assert: setup does not open over it — the files are on disk, so setup counts
them as settled and it is the engine that fails on them — `Specs/Setup.md`.
Assert: it is the same mark unfinished setup draws — both mean dictation cannot
happen and only the user can change that.
Assert: the menu says which of the two it is, since the icon does not: it names
the failure the engine recorded, in a line of its own, in the place
**Finish Setup…** would otherwise take.
Assert: **Start Listening** is not offered, since it could not work.
Assert: the menu offers **Try Again**, which brings the engine up again, and
**Re-download Models**, which deletes the Hot Word models and every
transcription model from disk and opens the setup window.

## A transcription model that will not load shows the same exclamation

1. Quit Overhear after a completed setup, with Whisper Base active.
2. Truncate `AudioEncoder.mlmodelc/model.mil` in Whisper Base's folder under
   `~/Library/Application Support/Overhear/whisper/` to a few bytes, so the
   folder still holds its `.mlmodelc` bundles but Whisper cannot load them.
3. Open Overhear.
4. Look at the menu bar icon, then click it.

Assert: the icon shows the exclamation rather than the idle dot.
Assert: setup does not open over it — the files are on disk, so setup counts
them as settled and it is the engine that fails on them — `Specs/Setup.md`.
Assert: it is the same mark unfinished setup draws — both mean dictation cannot
happen and only the user can change that.
Assert: the menu says which of the two it is, since the icon does not: it names
the failure the engine recorded, in a line of its own, in the place
**Finish Setup…** would otherwise take.
Assert: **Start Listening** is not offered, since it could not work.
Assert: the menu offers **Try Again**, which brings the engine up again, and
**Re-download Models**, which deletes the Hot Word models and every
transcription model from disk and opens the setup window.

## A failed batch keeps dictation running

1. Start dictation with TextEdit focused and the overlay shown.
2. Say `HelloEn`, pause two seconds, and let it arrive.
3. Delete the active model's folder under
   `~/Library/Application Support/Overhear/whisper/` while dictation is still
   running.
4. Say `SentenceEn` and pause two seconds.

Assert: the menu bar icon stays in its dictating states throughout — speaking
sends its ring out, pausing draws one in, and the exclamation never appears.
Assert: the overlay says the utterance could not be transcribed, in red for
about a second the way the cancel word is shown, then returns to "Ready".
Assert: nothing is inserted into the document for that utterance.
Assert: the menu offers **Stop Listening**, as it did before.
Assert: dictation is still active afterwards, ready for the next utterance.
Assert: the failure leaves nothing behind — nothing in the menu names it once
the next utterance has transcribed.

## Repeated failures stop the engine

1. From the case above, with the model's folder still gone, say `HelloEn` three
   times, pausing two seconds after each.

Assert: dictation stops of its own accord rather than failing once per
utterance for as long as the user keeps speaking.
Assert: the overlay disappears.
Assert: the icon shows the exclamation, and the menu names the failure and
offers **Try Again** and **Re-download Models** — the same as a model that
would not load.

## Loading is told apart from idle

1. Open Overhear with setup complete and watch the icon before the model
   finishes loading.

Assert: the dot pulses while the model loads and is still once it is ready.
Assert: the pulsing dot is brighter than the idle one at every point in its
cycle, so a glance never mistakes one for the other.
Assert: the pulse is even — it does not read as progress towards anything,
because nothing here knows how long the load will take.

## Menu contents while idle

1. Ensure dictation is stopped.
2. Click the menu bar icon.

Assert: the menu offers **Start Listening**, **Last Transcriptions**,
**Settings…**, **About Overhear** and **Quit Overhear**.
Assert: with no transcriptions yet, the menu says so under
**Last Transcriptions**.

## Menu contents while the model loads

1. Open Overhear with setup complete.
2. Click the menu bar icon before the icon's dot stops pulsing.

Assert: **Start Listening** is replaced by **Loading the model…**, which is not
an action — it says what is happening and cannot be clicked, because dictation
cannot start before the weights are in memory.
Assert: the rest of the menu is unchanged.
Assert: opening the menu again once the dot has stopped pulsing offers
**Start Listening**.

It is every load rather than the launch. Changing a language or the cancel word
rebuilds the engine and passes through the same state, where the menu has the
same thing to say — `Specs/Languages.md`, `Specs/CancelWord.md`.

## Menu contents while dictating

1. Start dictation.
2. Click the menu bar icon.

Assert: **Start Listening** is replaced by **Stop Listening**.

## Start Listening shows the hotkey

1. Record ⌃⌥D as the listening hotkey in **Settings… → General**.
2. Ensure dictation is stopped and click the menu bar icon.

Assert: **Start Listening** shows ⌃⌥D against its right edge, the way any
menu item shows its shortcut.
Assert: choosing the item still starts dictation.
Assert: recording a different combination changes what the item shows the
next time the menu opens.
Assert: with no hotkey recorded the item shows no shortcut at all — not
⌘D, which would only work while this menu is already open —
`Specs/Settings.md`.

## Stop Listening shows the hotkey

1. With ⌃⌥D recorded, start dictation and click the menu bar icon.

Assert: **Stop Listening** shows ⌃⌥D, the same combination
**Start Listening** showed.
Assert: pressing the combination with the menu open stops dictation, as
choosing the item would.
Assert: **Loading the model…** and **Finish Setup…** show no shortcut —
the hotkey does nothing in either state, and a shortcut on a line that
cannot be clicked would say otherwise.

## Menu contents before setup is finished

1. Revoke microphone access in System Settings.
2. Click the menu bar icon.

Assert: **Finish Setup…** replaces **Start Listening**.
Assert: choosing it opens the setup window.
Assert: the same item appears whenever any of the four things setup covers is
missing, not only a permission — the Hot Word models included —
`Specs/Setup.md`.

## Menu contents when a Hot Word model is missing

1. Delete `~/Library/Application Support/Overhear/models/*.onnx` and open
   Overhear offline, with setup otherwise complete.
2. Click the menu bar icon.

Assert: the icon shows the setup exclamation, not the engine error state.
Assert: **Finish Setup…** replaces **Start Listening**, and choosing it opens
the setup window on the **Hot Word models** card.
Assert: the menu carries no download progress, no failure text and no
**Try Again** of its own — all three are on the card now, in a window the user
can see — `Specs/Setup.md`.

## Recent transcriptions accumulate

1. Start dictation with TextEdit focused.
2. Dictate six short utterances, pausing between each.
3. Open the menu bar menu.

Assert: **Last Transcriptions** lists five entries.
Assert: the most recent is first.
Assert: the oldest of the six is not listed.
Assert: entries longer than sixty characters are truncated with an ellipsis.

## Pasting a recent transcription

1. Dictate two utterances so both are listed.
2. Focus TextEdit at an empty line.
3. Open the menu bar menu and click the second entry.

Assert: that transcription is inserted at the cursor.
Assert: the list order is unchanged.
Assert: no new entry is added.

## Recent transcriptions clear on quit

1. Dictate several utterances.
2. Quit Overhear and open it again.
3. Open the menu bar menu.

Assert: **Last Transcriptions** is empty.

## Overlay appears with dictation

1. Confirm **Show overlay window while listening** is on.
2. Start dictation.

Assert: the overlay appears in the top-right corner of the main screen.
Assert: it reads "Ready" on a dark background.
Assert: speaking changes it to "Listening…" on a frosted background.
Assert: pausing changes it to "Transcribing…".
Assert: the cancel word changes it to "Cancelled" with red shaking bars for
about a second.
Assert: stopping dictation hides it.

## Overlay stop button

1. Start dictation so the overlay is visible.
2. Click the stop button on the overlay.

Assert: dictation stops.
Assert: the overlay disappears.
Assert: the menu bar menu offers **Start Listening**.

## Overlay can be moved

1. Start dictation so the overlay is visible.
2. Drag it to another position on screen.
3. Stop dictation and start it again.

Assert: the overlay can be dragged by its background.
Assert: it returns to the top-right corner when shown again.

## Overlay stays above other windows

1. Start dictation so the overlay is visible.
2. Focus a full-screen application.

Assert: the overlay remains visible.
Assert: it does not take focus from the application.

## Hiding the overlay from its own menu

1. Start dictation so the overlay is visible.
2. Click the options control on the overlay.
3. Choose **Don't Show the Overlay**.

Assert: the overlay disappears.
Assert: **Show overlay window while listening** is now off in
**Settings… → General**.
Assert: the overlay does not reappear on the next dictation session or after
relaunching.

## Overlay is suppressed when the setting is off

1. Turn **Show overlay window while listening** off.
2. Start dictation and speak.

Assert: no overlay appears in any state.
Assert: the menu bar icon still reflects each state.
