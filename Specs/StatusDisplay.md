# Status Display

The menu bar icon, its menu, and the floating overlay.

## Menu bar icon reflects the engine state

1. Open Overhear and watch the icon through a full cycle: loading, idle, start
   dictation, speak, pause for transcription, say the cancel word.

Assert: loading and idle show a microphone icon.
Assert: the ready state shows static bars in orange.
Assert: speaking shows animated bars in orange.
Assert: transcribing shows a spinner.
Assert: the cancel word shows shaking bars in red for about a second, then
returns to the ready state.

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

## Menu contents without permissions

1. Revoke microphone access in System Settings.
2. Click the menu bar icon.

Assert: **Grant Permissions…** replaces **Start Listening**.
Assert: choosing it opens the permissions window.

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
