# Overhear

A macOS menu bar app for dictation. Click to start, speak naturally, and your words are transcribed and pasted into whatever text field is active.

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
against a fake microphone — no models, no network, no audio hardware:

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

- `Overhear.app` — the app bundle
- `Overhear.zip` — zipped archive of the app and install script
- `install.sh` — dependency installer for target machines

## Installing on Another Mac

1. Unzip `Overhear.zip`
2. Clear the quarantine flag (required for unsigned apps):
   ```bash
   xattr -cr Overhear.app
   ```
3. Run the install script to set up Python dependencies:
   ```bash
   ./install.sh
   ```
4. Open `Overhear.app`
5. Grant **Microphone** access when prompted
6. Grant **Accessibility** access in System Settings > Privacy & Security > Accessibility (needed for pasting text)

## Usage

- The app runs in the menu bar — look for the microphone icon
- By default the app starts dictating on its own once it finishes loading; you can turn that off in Settings
- Otherwise, click the menu bar icon and select **Start Dictating** to begin
- Speak naturally — text is transcribed in batches and pasted into the active text field
- Say the cancel word — **"Hey Jarvis"** unless you've changed it — to throw away what you just said and keep dictating. The menu bar and overlay briefly show a shaking animation to confirm.
- Click **Stop Dictating** to end the session
- Recent transcriptions appear in the menu — click one to paste it again

### Settings

- **Start dictating on launch** — begin dictating automatically when the app finishes loading (on by default)
- **Show overlay window** — toggle the floating status overlay that appears during dictation
- **Cancel word** — which phrase discards the current utterance. Four are built in: Alexa, Hey Jarvis, Hey Mycroft, Hey Rhasspy.
- **Custom Hot Words** — install extra [openwakeword](https://github.com/dscripka/openWakeWord) `.onnx` models from a file or a URL to use as the cancel word. Installed models are stored in `~/Library/Application Support/Overhear/models/`.
- **Recognition Languages** — select which languages Whisper should recognize (defaults to English and Polish). Fewer languages improves accuracy. At least one must be selected.

Changing the cancel word or the language set restarts the engine automatically, which takes a
moment while the models reload. The two toggles apply immediately.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for details on the two-process design, communication protocol, and key technical decisions.
