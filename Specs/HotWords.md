# Hot Words

Managing the models that can act as the cancel word: the four built in, and
custom `.onnx` models the user installs.

## Lists the built-in words

1. Open **Settings… → Hot Words**.
2. Open the **Cancel word** picker.

Assert: the picker offers Alexa, Hey Jarvis, Hey Mycroft and Hey Rhasspy.
Assert: Alexa is selected on a fresh install.
Assert: the **Custom Hot Words** list is empty and says so.
Assert: the built-in words do not appear in the **Custom Hot Words** list.
Assert: no entry in either list carries a version suffix such as "V0.1".

## Installs a custom word from a file

1. Download an openWakeWord `.onnx` model to the Desktop.
2. Open **Settings… → Hot Words**.
3. Click **Install from file…**.
4. Select the downloaded model.

Assert: the file picker only offers `.onnx` files.
Assert: the model appears in **Custom Hot Words** under a name derived from the
filename, with underscores and hyphens replaced by spaces and each word
capitalised.
Assert: the model also appears in the **Cancel word** picker.
Assert: the file is copied to
`~/Library/Application Support/Overhear/models/`.

## Installs a custom word from a URL

1. Open **Settings… → Hot Words**.
2. Click **Install from URL…**.
3. Enter a URL ending in `.onnx` that serves a valid model.
4. Click **Download**.

Assert: a progress indicator appears while the download runs.
Assert: the model appears in **Custom Hot Words** when it completes.
Assert: the sheet closes on success.

## Rejects a URL that does not end in .onnx

1. Open **Settings… → Hot Words** and click **Install from URL…**.
2. Enter a URL ending in `.bin`.
3. Click **Download**.

Assert: an error explains that the URL must point to an `.onnx` file.
Assert: the sheet stays open.
Assert: nothing is added to **Custom Hot Words**.

## Reports a failed download

1. Open **Settings… → Hot Words** and click **Install from URL…**.
2. Enter a URL ending in `.onnx` that returns 404.
3. Click **Download**.

Assert: an error is shown in the sheet.
Assert: the sheet stays open.
Assert: nothing is added to **Custom Hot Words**.

## Cancels the URL sheet

1. Open **Settings… → Hot Words** and click **Install from URL…**.
2. Type a URL.
3. Click **Cancel**.

Assert: the sheet closes.
Assert: nothing is downloaded or added.
Assert: reopening the sheet shows an empty field and no error from the previous
attempt.

## Selects a custom word as the cancel word

1. Install a custom model trained on a distinctive phrase.
2. Open the **Cancel word** picker and select it.
3. Wait for the engine to reload.
4. Start dictation and say the custom phrase while speaking.

Assert: the batch is discarded and the cancelled state is shown.
Assert: `alexa` no longer cancels.

## Removes a custom word

1. Install a custom model.
2. Click the trash button next to it in **Custom Hot Words**.

Assert: the model disappears from the list.
Assert: the model disappears from the **Cancel word** picker.
Assert: the file is removed from
`~/Library/Application Support/Overhear/models/`.

## Removing the selected cancel word falls back to Alexa

1. Install a custom model and select it as the **Cancel word**.
2. Remove it with the trash button.

Assert: **Cancel word** changes to Alexa.
Assert: dictation still cancels on `alexa` after the engine reloads.

## Installing a file that replaces an existing one

1. Install a model named `my_word.onnx`.
2. Install a different model with the same filename.

Assert: the list still shows one entry for that name.
Assert: the newer file is the one on disk.

## Built-in models cannot be removed

1. Open **Settings… → Hot Words** with no custom models installed.

Assert: no trash button is offered for Alexa, Hey Jarvis, Hey Mycroft or Hey
Rhasspy.
Assert: `melspectrogram.onnx` and `embedding_model.onnx` are not listed
anywhere in the interface.

## A model of the wrong format fails silently [to review]

1. Rename any unrelated `.onnx` file — one that is not an openWakeWord
   classifier — to `broken_word.onnx`.
2. Install it from file.
3. Select it as the **Cancel word** and wait for the engine to reload.
4. Start dictation and say `alexa`, then say the phrase the model was meant for.

Assert: the user is told the model cannot be used.

The model is accepted, appears in the list, and can be selected. Every
prediction against it fails and the failure is discarded, so the cancel word
never fires and no error is shown. Dictation otherwise works normally.

## Restoring a deleted models directory

1. Quit Overhear.
2. Delete `~/Library/Application Support/Overhear/models/`.
3. Open Overhear.

Assert: the setup window reappears and re-downloads the built-in models.
Assert: custom models deleted along with the directory are not restored.
Assert: **Cancel word** falls back to Alexa if the selected custom model is gone.
