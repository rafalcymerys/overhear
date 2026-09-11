# Overhear

https://github.com/user-attachments/assets/cace2a45-962c-43e6-a9db-f6af1518350d

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

Speech recognition runs locally. Transcription runs on the Neural Engine through
CoreML, with a choice of two engines — [WhisperKit](https://github.com/argmaxinc/WhisperKit)
for Whisper, and [FluidAudio](https://github.com/FluidInference/FluidAudio) for NVIDIA's
Parakeet — and voice commands use [openWakeWord](https://github.com/dscripka/openWakeWord)'s
models. Your audio never leaves your Mac; the models are downloaded once during setup
and everything after that is offline.

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
- **A choice of transcription model.** Whisper trades speed for accuracy across its
  five sizes; Parakeet is considerably faster and covers English or twenty-four
  languages. You pick one in Settings and can swap it at any time.
- **Push to talk, if you'd rather.** Always-on listening is the default, but you can
  record a hotkey and switch to **Hold to talk**: Overhear then listens only while
  you hold the key, and transcribes what you said when you let go.

Overhear is built from source (see below) and is not code-signed, so installing it
means clearing the quarantine flag yourself.

## Requirements

- A Mac with Apple silicon (M1 or later). Transcription and the wake word run on
  the Neural Engine, and the app is built for arm64 only — an Intel Mac cannot
  run it or build it.
- macOS 14 (Sonoma) or later
- Xcode 16 or later, to build it

## Development Setup

Clone the repo, then build and run — Swift Package Manager fetches everything,
and the app downloads its models on first launch:

```bash
swift build
.build/debug/Overhear
```

### Testing

```bash
swift test
```

The suite drives the dictation loop with a scripted microphone and the real wake
word models, so batching, the cancel word and the stop rules are checked against
actual inference rather than a stub. It downloads about 6MB of models the first
time.

Transcription tests are opt-in, because they pull down a few hundred megabytes of
model weights:

```bash
OVERHEAR_RUN_MODEL_TESTS=1 swift test --filter WhisperTranscriberTests
OVERHEAR_RUN_MODEL_TESTS=1 swift test --filter ParakeetTranscriberTests
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

- `Overhear.app`: the app bundle — a single self-contained binary
- `Overhear.zip`: zipped archive of the app

The bundle is signed with the first Developer ID Application certificate in
your keychain, or with the one you name:

```bash
./scripts/build.sh --identity "Developer ID Application: Jane Doe (AB12CD34EF)"
```

Signing matters beyond distribution: macOS remembers the accessibility
permission against the signing identity, so an unsigned build is a new app to
it every time you rebuild, and each new build finds the permission missing
however many times you have granted it.

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
3. Open `Overhear.app`. A setup window lists the four things dictation needs: a
   **transcription model**, the **Hot Word models** that hear your cancel word,
   and the **Microphone** and **Accessibility** permissions — to hear you, and
   to paste transcriptions into your apps. All four are required before
   dictation starts.
4. Pick a model and it downloads into `~/Library/Application Support/Overhear`,
   which you can do while granting the permissions. Nothing is fetched until you
   ask for it, apart from the Hot Word models: there is nothing to choose about
   those, so their card starts on its own and shows its progress alongside the
   rest. This only happens once; the app starts listening as soon as setup
   finishes, and you can install other models later from Settings.

macOS only offers its permission dialog once per launch. If you dismiss one, the
button turns into **Open System Settings** — flip the switch under Privacy &
Security there and the app picks it up on its own. You can reopen the window any
time from **Finish Setup…** in the menu bar.

That first run needs a network connection. Nothing else has to be installed —
the app carries its own inference engine.

## Usage

- The app runs in the menu bar, marked by the microphone icon
- By default the app starts listening on its own once it finishes loading; you can turn that off in Settings
- Otherwise, click the menu bar icon and select **Start Listening** to begin
- Speak naturally; text is transcribed in batches and pasted into the active text field
- Say the cancel word (**"Alexa"** unless you've changed it) to throw away what you just said and keep dictating. The menu bar and overlay briefly show a shaking animation to confirm.
- Click **Stop Listening** to end the session
- Recent transcriptions appear in the menu; click one to paste it again

### Settings

Settings is split into three panes.

**General**

- **Show overlay window while listening**: toggle the floating status overlay that appears while dictation is active
- **Listening Mode**, a group of three:
  - **Always-on listening** or **Hold to talk**: how listening starts and stops. Always-on listening is a toggle — press once to start, again to stop — and is what a fresh install uses. Hold to talk listens for as long as you hold the key: letting go transcribes what you said and ends the session, so a bare modifier such as Right Option, which types nothing while it is down, makes a good combination for it. In hold to talk the key is the only way in and out, so the menu says **Hold ⌃⌥D to talk** in place of **Start Listening**.
  - **Listening hotkey**: the combination itself, which works from whichever app you're typing in. Nothing is set until you record one — click the row and press the combination, or hold a single modifier such as Right Option and let it go. The menu bar item shows whatever is recorded.
  - **Start listening on launch**: begin listening automatically when the app finishes loading (on by default). Disabled while **Hold to talk** is chosen, which has no key held at launch — it keeps its value for when you switch back.
- **Strip transcription annotations**: drop the `(coughing)`-style notes a model sometimes writes instead of transcribing (on by default)
- **Ensure spaces around inserted text**: put a space between what's already in the field and what's pasted into it, and one on each side when you dictate into the middle of a sentence (on by default). Fields that don't say where the cursor is — a terminal, a password field — get the text exactly as transcribed.

**Transcription**

- **Active Model**: which model transcribes, with the languages it recognizes and whether it can translate. Selecting languages narrows what the engine is given — fewer languages improves accuracy, and at least one must be selected.
- **Available Models**: everything Overhear can run, grouped by engine, each one downloadable and removable. Whisper offers Tiny, Base, Base English, Small and Large v3 Turbo. Parakeet offers TDT 0.6B v2 for English and v3 across twenty-four languages. One model is active at a time, and the active one can't be removed.

A model that doesn't support a language you've selected leaves it inert rather than
forgetting it — going back to a model that does brings it back. Translation is
Whisper's alone, so the toggle sits disabled under Parakeet.

**Hot Words**

- **Cancel word**: which phrase discards the current utterance. Four are built in: Alexa, Hey Jarvis, Hey Mycroft, Hey Rhasspy.
- **Custom Hot Words**: install extra [openwakeword](https://github.com/dscripka/openWakeWord) `.onnx` models from a file or a URL to use as the cancel word. Installed models are stored in `~/Library/Application Support/Overhear/models/`.

Changing the cancel word or the language set restarts the engine automatically, which takes a
moment while the models reload. Activating a different model reloads it right away. The
toggles apply immediately.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the engine design and the key technical decisions.
