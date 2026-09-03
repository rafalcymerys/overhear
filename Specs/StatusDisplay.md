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

## An engine that failed to load shows the same exclamation

1. Delete `melspectrogram.onnx` from
   `~/Library/Application Support/Overhear/models/` and open Overhear.
2. Look at the menu bar icon.

Assert: the icon shows the exclamation rather than the idle dot.
Assert: it is the same mark unfinished setup draws — both mean dictation cannot
happen and only the user can change that.
Assert: the menu says which of the two it is, since the icon does not.

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

## Menu contents while dictating

1. Start dictation.
2. Click the menu bar icon.

Assert: **Start Listening** is replaced by **Stop Listening**.

## Menu contents before setup is finished

1. Revoke microphone access in System Settings.
2. Click the menu bar icon.

Assert: **Finish Setup…** replaces **Start Listening**.
Assert: choosing it opens the setup window.
Assert: the same item appears whenever any of the three things setup covers is
missing, not only a permission — `Specs/Setup.md`.

## Menu contents after a background download fails

1. Delete `~/Library/Application Support/Overhear/models/` and open Overhear
   offline, with setup otherwise complete.
2. Click the menu bar icon.

Assert: the icon shows the error state.
Assert: the menu says which file could not be downloaded, in place of
**Start Listening**.
Assert: the menu offers **Try Again**.
Assert: neither **Finish Setup…** nor the setup window appears — the wake word
models are not something the user chose.

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
