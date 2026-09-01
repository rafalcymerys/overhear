# Settings

The settings window: its three panes, the controls in each, and how changes
persist.

## Opens on the General pane

1. Click the menu bar icon and choose **Settings…**.

Assert: the window opens with a toolbar of three items: General, Transcription
and Hot Words.
Assert: General is selected and its toolbar item is highlighted.
Assert: the window title is "General".

## Switches panes

1. Open Settings.
2. Click **Transcription**.
3. Click **Hot Words**.
4. Click **General**.

Assert: each click changes the window title to the pane name.
Assert: the window resizes to fit each pane, with General shortest and
Transcription tallest.
Assert: the window stays anchored at its top-left corner while resizing.
Assert: the pane's contents appear only after the resize completes.
Assert: clicking the pane that is already selected does nothing.

## Scrolls the language list

1. Open **Settings… → Transcription**.
2. Open the **Languages** pull-down in the **Active Model** card.
3. Scroll to the bottom of the language list.

Assert: the window does not grow to fit the whole list.
Assert: the list scrolls inside the pull-down.
Assert: the search field at the top of the pull-down stays reachable.

## General pane contents

1. Open **Settings… → General**.

Assert: the pane offers **Start listening on launch**, **Show overlay window
while listening**, **Strip transcription annotations** and **Translate
unsupported languages**.
Assert: on a fresh install the first three are on and the fourth is off.
Assert: the transcription settings sit under a **Transcription** heading.
Assert: each transcription setting's explanation appears inside the same group
box as its checkbox.

## Toggles apply immediately

1. Start dictation and confirm the overlay is visible.
2. Open **Settings… → General** and turn **Show overlay window while listening**
   off.

Assert: the overlay disappears at once.
Assert: dictation stays active.
Assert: no engine reload happens.
Assert: turning it back on makes the overlay reappear while dictation is active.

## Start listening on launch

1. Open **Settings… → General** and turn **Start listening on launch** off.
2. Quit Overhear and open it again.
3. Wait for loading to finish.

Assert: dictation does not activate on its own.
Assert: the menu bar menu offers **Start Listening**.
Assert: turning the setting back on and relaunching activates dictation
automatically.

## Settings persist across restarts

1. Change every setting from its default: turn the three General toggles to
   their opposite, pick a different cancel word, activate a different model,
   and change the language selection.
2. Quit Overhear and open it again.
3. Open each settings pane.

Assert: every changed setting keeps its new value.
Assert: a setting turned off stays off rather than reverting to its default.

## Reopening settings returns to General [to review]

1. Open Settings and switch to **Transcription**.
2. Close the window.
3. Open **Settings…** again.

Assert: the window opens on the pane last used, or on General consistently.

The window always opens on General regardless of the pane last viewed.

## Settings window can be reopened after closing

1. Open Settings and close it.
2. Choose **Settings…** from the menu bar menu again.

Assert: the window reopens.
Assert: it is positioned and sized as before.
Assert: no duplicate window appears.

## Opening settings from the overlay

1. Start dictation so the overlay appears.
2. Click the options control on the overlay.
3. Choose **Settings…**.

Assert: the settings window opens.
Assert: dictation stays active.
