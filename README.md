# Overhear

https://github.com/user-attachments/assets/74f998b1-277d-4e29-b3cb-1c55529f27c9

Dictation for macOS that lives in your menu bar. Launch it and it starts listening on
its own. Whatever you say is transcribed and pasted into whichever text field is
focused, be it a Slack message, a commit message, a code comment, a browser form. It
works in the background, with no shortcuts or hotkeys to remember. Once you launch it,
it just keeps transcribing anytime it hears you say something, and you can pause it at
any time.

I built it for myself, because I often jump between responding to Slack messages,
writing documents, chatting with Claude and so on. Some of these tools require a push
of a button, some don't offer a native transcription at all. The idea is to just launch
it, and then talk to my computer whenever I need to enter text. It doesn't try to
correct mistakes automatically, because it's usually easier to just use the keyboard
for simple edits and fixes.

Speech recognition runs locally, using [faster-whisper](https://github.com/SYSTRAN/faster-whisper)
for transcription and [openwakeword](https://github.com/dscripka/openWakeWord) for
voice commands. Your audio never leaves your Mac; the models are downloaded once
during setup and everything after that is offline.

**What it's good at**

- **Long-form transcription.** Speech is transcribed in batches as you pause, so you
  can keep talking for as long as you like instead of dictating one sentence at a
  time and starting over.
- **Transcription in apps that don't offer it natively.** Text is delivered through
  the clipboard and a simulated Cmd+V, so it lands in anything that accepts a paste,
  including apps with no dictation support of their own.
- **Multiple languages.** You can pick the languages you use and it detects
  automatically which one you're speaking, so you can answer an email in Polish and go
  back to English without switching modes.

Overhear is built from source (see below) and is not code-signed, so installing it
means clearing the quarantine flag yourself.

## Requirements

- macOS 14 (Sonoma) or later
- Python 3.10+
- Xcode Command Line Tools (`xcode-select --install`)

## Development Setup

Clone the repo and run the setup script to create a Python virtual environment with all dependencies:

```bash
./scripts/setup.sh
```

This installs openwakeword, faster-whisper, and downloads the required models.

Then build and run:

```bash
swift build
.build/debug/Overhear
```

### Testing

The Python engine has an integration test suite that runs it as a real subprocess
against a fake microphone, with no models, no network, and no audio hardware:

```bash
.venv/bin/python -m pytest Engine
```

`./scripts/setup.sh` installs the test dependencies. Add `--run-slow` to also
load the real models and check transcription end to end. Every push and pull
request runs the fast lane on CI. See [TESTING.md](TESTING.md).

### Linting

SwiftLint is included as an SPM plugin and runs as a pre-commit hook. To lint manually:

```bash
swift package plugin --allow-writing-to-package-directory swiftlint lint
```

## Building for Distribution

To create a distributable `.app` bundle:

```bash
./scripts/build.sh
```

This produces a `dist/` folder containing:

- `Overhear.app`: the app bundle, with the installer inside it
- `Overhear.zip`: zipped archive of the app

To wrap the built bundle in a drag-to-install disk image:

```bash
./scripts/make-dmg.sh
```

This adds `dist/Overhear.dmg`, containing the app next to an `Applications`
shortcut. Both artifacts are also built by the **Release build** workflow on
every push to `main`; pushing a `v*` tag attaches them to a GitHub Release.

## Installing on Another Mac

1. Open `Overhear.dmg` and drag Overhear to Applications (or unzip
   `Overhear.zip`)
2. Clear the quarantine flag (required for unsigned apps):
   ```bash
   xattr -cr /Applications/Overhear.app
   ```
3. Open `Overhear.app`. It first asks for the two permissions dictation needs —
   **Microphone**, to hear you, and **Accessibility**, to paste transcriptions
   into your apps — with a button for each. Both are required before anything
   else happens.
4. Once they're granted, first launch creates the Python environment in
   `~/Library/Application Support/Overhear` and downloads the speech models,
   showing progress in a setup window. This takes a few minutes and only
   happens once; the app starts listening as soon as it finishes.

macOS only offers its permission dialog once per launch. If you dismiss one, the
button turns into **Open System Settings** — flip the switch under Privacy &
Security there and the app picks it up on its own. You can reopen the window any
time from **Grant Permissions…** in the menu bar.

The Mac needs Python 3.10+ (`brew install python3`) and a network connection for
that first run. To do the setup step from the terminal instead — useful if you
want to watch it, or install on several machines — run the installer inside the
bundle before opening the app:

```bash
./Overhear.app/Contents/Resources/install.sh
```

The app then detects the finished environment and skips straight to listening.
Setup output is logged to `~/Library/Application Support/Overhear/install.log`.

## Usage

- The app runs in the menu bar, marked by the microphone icon
- By default the app starts listening on its own once it finishes loading; you can turn that off in Settings
- Otherwise, click the menu bar icon and select **Start Listening** to begin
- Speak naturally; text is transcribed in batches and pasted into the active text field
- Say the cancel word (**"Alexa"** unless you've changed it) to throw away what you just said and keep dictating. The menu bar and overlay briefly show a shaking animation to confirm.
- Click **Stop Listening** to end the session
- Recent transcriptions appear in the menu; click one to paste it again

### Settings

- **Start listening on launch**: begin listening automatically when the app finishes loading (on by default)
- **Show overlay window while listening**: toggle the floating status overlay that appears while dictation is active
- **Cancel word**: which phrase discards the current utterance. Four are built in: Alexa, Hey Jarvis, Hey Mycroft, Hey Rhasspy.
- **Custom Hot Words**: install extra [openwakeword](https://github.com/dscripka/openWakeWord) `.onnx` models from a file or a URL to use as the cancel word. Installed models are stored in `~/Library/Application Support/Overhear/models/`.
- **Recognition Languages**: select which languages Whisper should recognize. Fewer languages improves accuracy. At least one must be selected.

Changing the cancel word or the language set restarts the engine automatically, which takes a
moment while the models reload. The two toggles apply immediately.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for details on the two-process design, communication protocol, and key technical decisions.
