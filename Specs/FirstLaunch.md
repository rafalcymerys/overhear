# First Launch

Covers the path from an unopened app to a working engine: permissions, model
download, and the states in between.

## Grants both permissions from the permissions window

1. Remove `~/Library/Application Support/Overhear/` and reset the app's
   microphone and accessibility grants in System Settings.
2. Open Overhear.
3. Observe the window titled "Overhear Permissions".
4. Click **Grant Microphone Permission** and allow the macOS dialog.
5. Click **Grant Permission for Inserting Text** and allow the macOS dialog.

Assert: the permissions window lists exactly two permissions, Microphone and
Inserting text in your apps.
Assert: each granted permission's button is replaced by a checkmark.
Assert: the permissions window closes on its own once both are granted.
Assert: setup continues without further clicks.

## Dismisses a macOS permission dialog

1. Start from the permissions window with neither permission granted.
2. Click **Grant Microphone Permission**.
3. Dismiss the macOS dialog without allowing.
4. Observe the button.

Assert: the button changes to open the relevant System Settings pane.
Assert: clicking it opens System Settings at Privacy & Security.
Assert: granting the permission in System Settings updates the window within
about a second, without restarting the app.

## Closes the permissions window before granting

1. Start from the permissions window with neither permission granted.
2. Close the window.
3. Click the menu bar icon.

Assert: the menu shows **Grant Permissions…** in place of **Start Listening**.
Assert: choosing **Grant Permissions…** reopens the permissions window.
Assert: a permission granted in System Settings while the window is closed is
picked up the next time the menu bar menu is opened.

## Downloads the models on first launch

1. Remove `~/Library/Application Support/Overhear/`.
2. Open Overhear with both permissions already granted.
3. Observe the window titled "Overhear Setup".
4. Wait for it to finish.

Assert: the setup window states that models are being downloaded and that it
happens once.
Assert: progress counts through the files being fetched.
Assert: `~/Library/Application Support/Overhear/models/` ends up containing
`alexa.onnx`, `hey_jarvis.onnx`, `hey_mycroft.onnx`, `hey_rhasspy.onnx`,
`melspectrogram.onnx` and `embedding_model.onnx`.
Assert: no file name contains a version suffix.
Assert: the setup window closes on its own when the download finishes.

## Recovers from a failed model download

1. Remove `~/Library/Application Support/Overhear/models/`.
2. Disconnect from the network.
3. Open Overhear.
4. Wait for the download to fail.
5. Reconnect to the network and click **Try Again**.

Assert: the setup window shows which file could not be downloaded.
Assert: the window offers **Try Again** and **Quit**.
Assert: the models directory contains no partial files after the failure.
Assert: **Try Again** completes the download and the app reaches idle.

## Skips setup on subsequent launches

1. Quit Overhear after a completed first launch.
2. Open it again.

Assert: no setup window appears.
Assert: no permissions window appears.
Assert: nothing is re-downloaded.

## Starts listening on launch by default

1. Open Overhear with setup already complete and **Start listening on launch**
   on.
2. Wait for the engine to finish loading.

Assert: dictation activates without any click.
Assert: the menu bar icon shows the active state.
Assert: the menu bar menu offers **Stop Listening**.

## Engine failure is only visible as an icon [to review]

1. Quit Overhear.
2. Delete `melspectrogram.onnx` from
   `~/Library/Application Support/Overhear/models/`.
3. Open Overhear.
4. Click the menu bar icon.

Assert: the menu bar icon shows the error state.
Assert: the reason for the failure is available to the user somewhere in the UI.

The engine records a message describing the failure, and no part of the
interface displays it. The menu offers **Start Listening** as though nothing is
wrong.
