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
- Click the menu bar icon and select **Start Dictating** to begin
- Speak naturally — text is transcribed in batches and pasted into the active text field
- Say **"Hey Jarvis"** to cancel the current transcription and keep listening
- Click **Stop Dictating** to end the session
- Recent transcriptions appear in the menu — click one to paste it again

### Settings

- **Show overlay window** — toggle the floating status overlay that appears during dictation
- **Recognition Languages** — select which languages Whisper should recognize (defaults to English and Polish). Fewer languages improves accuracy. Changes restart the engine automatically.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for details on the two-process design, communication protocol, and key technical decisions.
