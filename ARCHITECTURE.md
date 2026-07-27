# Overhear — Architecture

A macOS menu bar app for dictation. Click to start dictating, speak naturally, and your words are transcribed and pasted into whatever text field is active.

## Core Concept

Overhear runs silently in the menu bar. Clicking **Start Dictating** enters dictation mode: the app continuously captures speech in batches, transcribes each batch when you pause, and injects the text into the focused application. Clicking **Stop Dictating** (or pressing Stop in the overlay) deactivates dictation. If **Start dictating on launch** is enabled (the default), the app activates dictation by itself as soon as the engine finishes loading.

During dictation, saying the **cancel word** — "Hey Jarvis" by default — discards whatever is currently being heard or transcribed. The batch is dropped and the app returns to the ready state, still listening for the next utterance. The cancel word is configurable in Settings: four openwakeword models ship built in (Alexa, Hey Jarvis, Hey Mycroft, Hey Rhasspy), and additional `.onnx` models can be installed. See [Hot Words](#hot-words).

> Terminology: the feature is called the *cancel word* in the UI and in the engine's `--cancel-word` argument, but the underlying library is a wake-word detector, so the event it produces is still named `wake_word_cancel`.

## Architecture: Two-Process Split

The app is split into a **Swift host** (UI, macOS integration) and a **Python engine** (ML inference, audio capture). They communicate over stdin/stdout using JSON lines.

```
+---------------------------+          JSON lines          +---------------------------+
|       Swift Host          | <------------------------->  |      Python Engine         |
|                           |    stdin:  commands           |                           |
|  - Menu bar icon          |    stdout: events             |  - Audio capture           |
|  - Floating overlay UI    |                               |    (sounddevice)           |
|  - Text injection         |                               |  - Wake word detection     |
|  - Settings (UserDefaults)|                               |    (openwakeword + ONNX)   |
|  - Engine lifecycle       |                               |  - Speech transcription    |
+---------------------------+                               |    (faster-whisper)        |
                                                            +---------------------------+
```

### Why two processes?

- **openwakeword** and **faster-whisper** are Python libraries with no native Swift bindings. Wrapping them via C/ONNX Runtime would be complex and fragile.
- A subprocess keeps the ML dependencies isolated — the Swift app stays lean and the Python environment is managed by a venv.
- JSON-line IPC is simple, debuggable, and allows the engine to be tested independently.

## Communication Protocol

### Launch arguments (Swift -> Python)

The engine is configured once per launch, via argv rather than commands. Changing either setting
restarts the engine (see [Settings](#settings)).

| Argument | Default | Meaning |
|---|---|---|
| `--languages` | `en` | Comma-separated Whisper language codes to recognize |
| `--cancel-word` | `hey_jarvis` | A built-in openwakeword model name, or an absolute path to a custom `.onnx` model |

### Commands (Swift -> Python, via stdin)

```json
{"command": "activate"}
{"command": "deactivate"}
{"command": "quit"}
```

Unrecognized commands and malformed JSON lines are ignored — the engine keeps running.

### Events (Python -> Swift, via stdout)

| Event | Fields | Meaning |
|---|---|---|
| `status` | `message` | Loading progress (`loading_models`, `wake_word_ready`, `whisper_ready`) |
| `config` | `languages` | Echoes the resolved language set at startup, for diagnostics |
| `idle` | — | Engine initialized or dictation stopped — waiting for activation |
| `ready` | — | Dictation active, waiting for speech |
| `speech_start` | — | Audio level crossed silence threshold — user is speaking |
| `transcribing` | — | Processing a batch of speech |
| `transcription` | `text` | Result — triggers paste |
| `language_detected` | `language` | Which language was used for this transcription |
| `wake_word_cancel` | — | Cancel word said during dictation — current batch discarded, stays in dictation |
| `warning` | `message` | Non-fatal issue (e.g. audio device changed) |
| `error` | `message` | Something went wrong |

Each event is a single line of JSON on stdout, written with `ensure_ascii=False` so non-Latin
transcriptions travel as UTF-8 rather than escapes. Newlines inside `text` are escaped by
`json.dumps`, so the line framing holds for any transcription.

Two events carry no UI behaviour today: `config` and `language_detected` are emitted for
diagnostics and ignored by the host.

## Engine States

The engine and UI share a unified state model:

| State | Engine event | Menu bar | Overlay | Description |
|---|---|---|---|---|
| **Stopped** | — | Mic icon | Hidden | App not started |
| **Loading** | `status` | Mic icon | Hidden | Loading ML models |
| **Idle** | `idle` | Mic icon | Hidden | Ready to be activated via menu |
| **Ready** | `ready` | Static bars, orange | "Ready" (dark bg) | Dictation active, waiting for speech |
| **Listening** | `speech_start` | Animated bars, orange | "Listening..." (material bg) | Actively hearing speech |
| **Transcribing** | `transcribing` | Spinner, dark orange | "Transcribing..." (material bg) | Processing with Whisper |
| **Cancelled** | `wake_word_cancel` | Shaking bars, red (1s) | Shaking bars + "Cancelled" (1s) | Cancel word discarded current batch |
| **Error** | `error` | Error icon | Hidden | Something failed |

After transcription completes, the engine returns to **Ready** if still dictating. The **Cancelled** state is a 1-second visual indicator triggered by the cancel word — it overlays on top of the current state and returns to **Ready** automatically.

## Swift Host — Key Components

| File | Role |
|---|---|
| `OverhearApp.swift` | App entry point, accessory (no dock icon) |
| `AppDelegate.swift` | Menu bar setup (Start/Stop Dictating, recent transcriptions, Settings, About, Quit), engine lifecycle, settings observation |
| `AppState.swift` | Observable state enum: stopped, loading, idle, ready, listening, transcribing, error |
| `EngineProcess.swift` | Launches Python subprocess, reads JSON events, dispatches to AppState |
| `OverlayWindow.swift` | Floating status window (top-right corner) — shows Ready/Listening/Transcribing/Result |
| `MenuBarIcon.swift` | SwiftUI view embedded in NSStatusItem — animated bars, static bars, spinner depending on state |
| `TextInjector.swift` | Pastes transcribed text via pasteboard + simulated Cmd+V, restores previous clipboard |
| `Settings.swift` | `AppSettings` (UserDefaults-backed), `WhisperLanguage` catalog with flags, `HotWord` model |
| `SettingsView.swift` | Grouped form with language chips, searchable language list, toggles, hot word management |
| `HotWordService.swift` | Discovers, installs (file or URL), and removes custom `.onnx` cancel word models |

## Menu Bar

The menu dynamically updates via `NSMenuDelegate`:

- **Start Dictating / Stop Dictating** — toggles dictation (changes label based on state)
- **Last Transcriptions** — up to 5 recent transcriptions; clicking one pastes it into the active app
- **Settings...** — opens the settings window
- **About Overhear** — standard macOS about panel
- **Quit Overhear**

## Settings

All settings live in `AppSettings.shared`, backed by `UserDefaults` and published via Combine.

| Setting | Key | Default | Effect |
|---|---|---|---|
| Start dictating on launch | `dictateOnLaunch` | on | Sends `activate` automatically on the first `idle` after launch |
| Show overlay window | `showOverlay` | on | Whether the floating overlay appears during dictation |
| Cancel word | `cancelWord` | Hey Jarvis | Which wake word model cancels the current batch |
| Recognition languages | `selectedLanguages` | `en`, `pl` | Whisper language set; at least one must be selected |

Because the engine takes its language set and cancel word as launch arguments, changing either one
requires a restart. `AppDelegate` observes both and calls `scheduleRestart()`, which debounces for
1 second before stopping and relaunching the engine — so toggling several languages in a row
produces a single restart rather than one per toggle. The overlay and launch toggles apply live
and never restart the engine.

## Hot Words

The cancel word is an openwakeword model. Four ship with the library and are always listed:
Alexa, Hey Jarvis, Hey Mycroft, Hey Rhasspy.

Custom models can be added in Settings, either from a local `.onnx` file or by URL. They are
copied into `~/Library/Application Support/Overhear/models/`, and `HotWordService` lists every
`.onnx` file in that directory at launch. The display name is derived from the filename —
`my_word.onnx` becomes "My Word". Removing a custom word deletes the file; if it was the selected
cancel word, the selection falls back to Hey Jarvis.

Built-in words are passed to the engine by name (`hey_jarvis`); custom ones are passed as an
absolute path. Both forms are accepted by `openwakeword`'s `wakeword_models` argument.

## Python Engine — Key Decisions

- **Audio capture**: `sounddevice` with 16kHz mono float32, 1280-sample chunks (80ms — what openwakeword expects).
- **Audio device recovery**: The audio stream is wrapped in a retry loop. When the default input device changes (e.g. AirPods connecting), a `warning` is emitted and the stream re-opens automatically after a 1-second delay. Dictation does **not** survive the swap — the engine drops back to idle and the user has to start dictating again.
- **Cancel word**: Audio is converted to int16 before passing to openwakeword (it expects int16, not float32). Detection threshold is 0.5. During dictation, the cancel word discards the current batch but does not stop dictation. It is checked in two places: on every chunk while recording, and — via `check_queued_wake_word` — against the audio that buffered up while Whisper was running, so a cancel spoken during transcription still suppresses the result. If no cancel word is found in that buffered audio, the chunks are put back on the queue so the next batch doesn't lose its opening words.
- **Dictation mode**: Records in batches — accumulates chunks until 1.5s of silence, then transcribes that batch and keeps listening. Batches are capped at 30s. A batch shorter than 0.3s, or one in which the level never crossed the silence threshold, is discarded without transcribing. Activated/deactivated via commands from the Swift host.
- **Language detection**: When multiple languages are configured, `detect_language()` runs first on the audio, scores are filtered to the selected language set, and the best match is used for transcription. Single language skips detection.
- **Whisper model**: `base` model with int8 quantization on CPU. Good balance of speed and accuracy for dictation.

## Text Injection

Uses the pasteboard approach rather than CGEvent key simulation or Accessibility API:

1. Save current clipboard contents
2. Copy transcribed text to pasteboard
3. Simulate Cmd+V via CGEvent
4. Restore previous clipboard after 300ms

This works reliably across all macOS apps without requiring Accessibility permissions for the target app.

## Overlay UI States

The floating window transitions between states with animated crossfades:

| State | Visual | Background |
|---|---|---|
| Ready | Static dots + "Ready" | Black 30% opacity |
| Listening | Animated audio bars + "Listening..." | Frosted material |
| Transcribing | Spinner + "Transcribing..." | Frosted material |
| Cancelled | Shaking red bars + "Cancelled" (1s) | Frosted material |

The overlay appears when dictation activates and hides when it deactivates. Can be toggled off in Settings.

## Linting

SwiftLint is included as an SPM plugin and runs automatically as a pre-commit hook. To lint manually:

```bash
swift package plugin --allow-writing-to-package-directory swiftlint lint
```

## Setup & Dependencies

**Python** (managed via venv):
- `openwakeword` — wake word detection (ONNX models)
- `faster-whisper` — CTranslate2-based Whisper inference
- `sounddevice` — cross-platform audio capture
- `numpy`

**Swift**: SwiftLint (via SPM plugin). Uses AppKit, SwiftUI, Combine, Carbon (for key codes).

```bash
./scripts/setup.sh   # creates venv, installs deps, downloads wake word models
swift build           # builds the Swift app
.build/debug/Overhear # run
```

## Permissions Required

- **Microphone**: prompted automatically by macOS on first audio capture
- **Accessibility**: needed for CGEvent-based Cmd+V paste simulation (System Settings > Privacy > Accessibility)
