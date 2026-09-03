# Setup

Covers the path from an unopened app to a working engine, and every later
return to it. One window titled "Overhear Setup" carries all of it: the
transcription model, the microphone, and the right to paste into other apps.

There is no separate permissions window. Nothing downloads on its own on a
fresh install — the model arrives because the user chose it here.

## Opens on first launch

1. Remove `~/Library/Application Support/Overhear/` and reset the app's
   microphone and accessibility grants in System Settings.
2. Open Overhear.

Assert: a window titled "Overhear Setup" appears.
Assert: it is headed **Let's get you set up**, followed by "To use Overhear,
you need to download a transcription model and grant some basic permissions."
Assert: it holds exactly three cards, in this order: **Choose a model**,
**Microphone**, and **Inserting text in your apps**.
Assert: the **Choose a model** card is expanded and the other two are collapsed
to their headings.
Assert: nothing has been downloaded — the models directory is still absent.
Assert: the window offers **Quit**, and quitting from it closes the app.

## The card that needs attention is the one that is open

1. Start from a fresh first launch.
2. Grant the microphone permission.

Assert: the topmost unfinished card is the expanded one at any moment.
Assert: a finished card collapses to a single line carrying a checkmark and
what it settled — **Granted** for a permission, the model's name and
**Downloaded** for the model.
Assert: a collapsed card can be clicked open, and an open one clicked shut,
without changing what has been granted or downloaded.
Assert: the window resizes to fit as cards open and close, and stays anchored
at its top-left corner.

## Chooses and downloads the preselected model

1. Start from a fresh first launch.
2. Read the **Choose a model** card.
3. Click **Download**.

Assert: the card explains that the model runs locally: "Download a model that
will be used locally on your Mac for the transcription. You can change it later
in settings."
Assert: the model control is preselected to Whisper Base and names its download
size.
Assert: no download starts until **Download** is clicked.
Assert: the card shows a progress indicator, how much of the download has
arrived, and a control to cancel it.
Assert: the card collapses to a checkmark, the model's name and **Downloaded**
when the download finishes.
Assert: the downloaded model becomes the active model.

## Chooses a different model

1. Start from a fresh first launch.
2. Open the model control in the **Choose a model** card.

Assert: the models are grouped by engine, as in **Settings… → Transcription**,
with each group's few words on what the engine is.
Assert: every model shows its name and download size, and no row carries a raw
repository or variant identifier.
Assert: on a Mac without Apple silicon the Parakeet group is absent.
Assert: picking another model changes what **Download** will fetch and nothing
else.
Assert: the model cannot be changed once its download is running — cancelling
it first puts the choice back.
Assert: picking an English-only model narrows the default language selection to
English once it is downloaded and active, the way activating one later does —
`Specs/TranscriptionModel.md`.

## Cancels the model download

1. Start a download of Whisper Large v3 Turbo from the setup window.
2. Click the cancel control.

Assert: the download stops and the card goes back to offering the model control
and **Download**.
Assert: no partial files are left in the models directory.
Assert: no model is active, and setup stays unfinished.

## Recovers from a failed model download

1. Disconnect from the network.
2. Start a download from the setup window and wait for it to fail.
3. Reconnect and click **Try Again**.

Assert: the card states that the download failed and why.
Assert: it offers **Try Again** and **Choose Another Model**.
Assert: no partial files are left behind.
Assert: the other two cards stay usable while the model card shows the failure.
Assert: **Try Again** completes the download.
Assert: **Choose Another Model** puts the model control back with the failed
model still selected, so a smaller one can be picked instead.

## Grants both permissions

1. Start from a fresh first launch.
2. Open the **Microphone** card and click **Grant Microphone Permission**, then
   allow the macOS dialog.
3. Open the **Inserting text in your apps** card and click **Grant Permission
   for Inserting Text**, then allow the macOS dialog.

Assert: the **Microphone** card explains "Overhear listens through your
microphone to hear what you dictate. Audio never leaves your Mac."
Assert: the **Inserting text in your apps** card explains "Transcriptions are
pasted into whatever app you're using. For this, Overhear needs the
accessibility permission."
Assert: each card collapses to a checkmark and **Granted** as it is allowed.
Assert: neither grant disturbs a download in progress.

## Works on all three at once

1. Start from a fresh first launch.
2. Click **Download** on the model card.
3. Without waiting for it, grant both permissions.

Assert: the download keeps running while the permission dialogs come and go.
Assert: the model card stays expanded showing its progress, and the microphone
card opens beneath it rather than waiting for the download.
Assert: the window closes on its own when the last of the three completes,
whichever it is.
Assert: the engine starts only once all three hold.

## Dismisses a macOS permission dialog

1. Start from the setup window with neither permission granted.
2. Click **Grant Microphone Permission**.
3. Dismiss the macOS dialog without allowing.

Assert: the button changes to **Open System Settings**.
Assert: clicking it opens System Settings at Privacy & Security.
Assert: the explanation in the card is unchanged.
Assert: granting the permission in System Settings updates the window within
about a second, without restarting the app.

## Closes the setup window before finishing

1. Start from the setup window with something still outstanding.
2. Close the window.
3. Click the menu bar icon.

Assert: the menu shows **Finish Setup…** in place of **Start Listening**.
Assert: choosing **Finish Setup…** reopens the window with the same cards
finished and unfinished as before.
Assert: a permission granted in System Settings while the window is closed is
picked up the next time the menu bar menu is opened.
Assert: a download running when the window was closed keeps running, and the
reopened window shows its progress.

## Skips setup when everything is in place

1. Quit Overhear after a completed setup.
2. Open it again.

Assert: no setup window appears.
Assert: nothing is re-downloaded.
Assert: the menu bar menu offers **Start Listening**.

## Opens again when a permission is revoked

1. Complete setup, then revoke Overhear's accessibility access in System
   Settings.
2. Open Overhear, or open the menu bar menu if it is already running.

Assert: the setup window opens, headed the same as on first launch.
Assert: the model and microphone cards are collapsed with checkmarks; the
accessibility card is the expanded one.
Assert: macOS does not show its own dialog for a permission it has already been
asked about, so the card offers **Open System Settings**.
Assert: the window closes on its own once the permission is restored, and
dictation becomes available again.

## Opens again when no model is downloaded

1. Quit Overhear after a completed setup.
2. Delete every downloaded model from
   `~/Library/Application Support/Overhear/`.
3. Open Overhear.

Assert: the setup window opens with both permissions collapsed and ticked.
Assert: the model card is the expanded one, preselected to the model that was
active before, not to Whisper Base.
Assert: the model is not re-downloaded until **Download** is clicked.
Assert: dictation becomes available once the download finishes, and not before.

## Opens again when the active model's files are gone

1. Quit Overhear with Whisper Small active and Whisper Base also downloaded.
2. Delete Whisper Small's files from
   `~/Library/Application Support/Overhear/`.
3. Open Overhear.

Assert: the setup window opens with the model card expanded and Whisper Small
selected.
Assert: Overhear does not quietly fall back to Whisper Base, and does not
re-download Whisper Small without being asked.
Assert: choosing Whisper Base in the card and clicking **Download** is allowed,
and makes Whisper Base the active model without downloading it again — it is
already on disk.
Assert: models other than the active one are not checked for missing files.

## Fetches the wake word models in the background

1. Remove `~/Library/Application Support/Overhear/`.
2. Complete setup.

Assert: the setup window never mentions the wake word models.
Assert: they are fetched after the window closes, without a window of their
own.
Assert: the menu bar icon shows the loading state while they arrive, and the
menu offers no **Start Listening** until they have.
Assert: `~/Library/Application Support/Overhear/models/` ends up containing
`alexa.onnx`, `hey_jarvis.onnx`, `hey_mycroft.onnx`, `hey_rhasspy.onnx`,
`melspectrogram.onnx` and `embedding_model.onnx`.
Assert: no file name contains a version suffix.

## Recovers from a failed wake word download

1. Remove `~/Library/Application Support/Overhear/models/`.
2. Disconnect from the network.
3. Open Overhear with setup otherwise complete.

Assert: the menu bar icon shows the error state.
Assert: the menu says which file could not be downloaded.
Assert: the menu offers **Try Again**, and reconnecting and choosing it
completes the download and reaches idle.
Assert: the models directory contains no partial files after the failure.
Assert: the setup window does not open — nothing the user chose is missing.

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
