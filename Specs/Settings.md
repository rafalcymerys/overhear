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

Assert: the pane offers **Show overlay window while listening**, a
**Listening Mode** group, and **Strip transcription annotations** and **Add
spaces around inserted text** under a **Transcription** heading, in that order.
Assert: **Show overlay window while listening** sits on its own above the
**Listening Mode** heading.
Assert: the **Listening Mode** group holds three things, in this order: the
choice between **Always-on listening** and **Hold to talk**, the **Listening
hotkey** row, and **Start listening on launch**.
Assert: on a fresh install all four toggles are on.
Assert: the hotkey row shows the combination as symbols, or **Record
Shortcut** when none is set.
Assert: **Always-on listening** is what a fresh install has.
Assert: **Always-on listening** carries an explanation below it, reading
"Overhear keeps listening in the background. Use the menu or the hotkey to
turn listening on and off."
Assert: the explanation sits with the option it describes, the way each
transcription setting's does.
Assert: translation is not offered here — it belongs to the active model, in
**Settings… → Transcription**.
Assert: the transcription settings sit under a **Transcription** heading.
Assert: **Ensure spaces around inserted text** carries the explanation its
own spec gives it, and what it does is specified in `Specs/Spacing.md`.
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
Assert: the toggle is always shown, and is enabled only while **Always-on
listening** is chosen — below.

## No hotkey is set on a fresh install

1. Install Overhear fresh and open **Settings… → General**.

Assert: the hotkey row reads **Record Shortcut** rather than a combination.
Assert: no combination starts listening until one is recorded.

Overhear ships without a default deliberately: any combination we picked
might already belong to the app the user is typing in.

## Records a hotkey

1. Open **Settings… → General**.
2. Click the hotkey row.
3. Press Ctrl+Option+D.

Assert: the row shows that it is waiting while it records.
Assert: the row then shows ⌃⌥D and stops recording.
Assert: the combination is not typed anywhere, and the settings window does
not act on it — recording a shortcut never triggers what it is bound to.
Assert: clicking elsewhere while recording leaves the previous combination
unchanged.
Assert: pressing Escape while recording cancels without changing anything.

## Records a modifier on its own

1. Click the hotkey row.
2. Hold Right Option briefly and release it.

Assert: the row shows the modifier as the recorded combination.
Assert: it is stored and re-registered like any other combination.

A bare modifier types nothing while held, which is what makes it the
combination hold to talk wants.

## Refuses a combination that is already taken

1. Click the hotkey row.
2. Press a combination macOS reserves, such as Cmd+Space.

Assert: the row says the combination is taken and keeps recording.
Assert: the previous combination, if any, stays in force.

## Clearing the hotkey

1. Record a hotkey and confirm it starts listening.
2. Open **Settings… → General** and clear the hotkey row.

Assert: the row returns to **Record Shortcut**.
Assert: the combination no longer starts listening.
Assert: it reaches the focused application again instead of being swallowed.
Assert: the mode choice above the row is unaffected, and stays on whichever
mode was chosen.
Assert: clearing it while **Hold to talk** is chosen leaves no way to dictate,
which the menu says in the line **Set a Listening Hotkey…** —
`Specs/Dictation.md`.

## A changed hotkey applies immediately

1. Record ⌃⌥D and confirm it toggles listening.
2. Open **Settings… → General** and record ⌃⌥L instead.

Assert: ⌃⌥L toggles listening without relaunching Overhear.
Assert: ⌃⌥D does nothing.
Assert: no engine reload happens, and dictation in progress is unaffected.

## Choosing hold to talk

1. Open **Settings… → General**.
2. Choose **Hold to talk**.

Assert: the choice sits at the top of the **Listening Mode** group, above the
row that gives it a combination.
Assert: it is offered whether or not a hotkey is recorded — it describes the
mode the app is in, and the row below it is where a combination is given to
that mode.
Assert: with no hotkey recorded the choice is still made and stored; the first
combination recorded afterwards is held rather than pressed, with no second
visit to settings.
Assert: it applies immediately — no relaunch and no engine reload.
Assert: dictation running when the mode changes is stopped, whichever mode it
was started in and whichever was chosen — `Specs/Dictation.md`.
Assert: **Start listening on launch** is shown but disabled, and has no effect
— there would be no key held and, in this mode, no **Stop Listening** to reach
the session with.
Assert: it keeps the value it was left with rather than reading as off.

## The launch toggle follows the mode

1. Open **Settings… → General** with **Always-on listening** chosen and
   **Start listening on launch** on.
2. Choose **Hold to talk**.
3. Choose **Always-on listening** again.

Assert: the toggle is enabled to begin with.
Assert: choosing **Hold to talk** disables it at once, with the window still
open and without the pane being left and returned to.
Assert: choosing **Always-on listening** again enables it at once.
Assert: it reads as on throughout — neither switch changes the value, only
whether the toggle can be reached.
Assert: the same holds for a toggle left off: it comes back off rather than
back on.
Assert: the value it ends on is the one that takes effect on the next launch.

## Settings persist across restarts

1. Change every setting from its default: turn the four General toggles to
   their opposite, record a listening hotkey, choose **Hold to talk** — in that
   order, since the last of those disables one of the toggles — pick a
   different cancel word, activate a different model, and change the language
   selection.
2. Quit Overhear and open it again.
3. Open each settings pane.

Assert: every changed setting keeps its new value.
Assert: a setting turned off stays off rather than reverting to its default.
Assert: the recorded hotkey still starts listening after the restart, in the
mode that was chosen.
Assert: **Start listening on launch** comes back disabled, still showing the
value it was given — a setting the mode has taken out of use is not a setting
that has been forgotten.

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
