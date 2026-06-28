# Overhear — Architecture

A macOS menu bar app for dictation. Click to start dictating, speak naturally, and your words are transcribed and pasted into whatever text field is active.

## Core Concept

Overhear runs silently in the menu bar. Clicking **Start Dictating** enters dictation mode: the app continuously captures speech in batches, transcribes each batch when you pause, and injects the text into the focused application. Clicking **Stop Dictating** (or pressing Stop in the overlay) deactivates dictation.

During dictation, saying the wake word **"Hey Jarvis"** cancels whatever is currently being heard or transcribed — the batch is discarded and the app returns to the ready state, still listening for the next utterance.

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

### Commands (Swift -> Python, via stdin)

```json
{"command": "activate"}
{"command": "deactivate"}
{"command": "quit"}
```

### Events (Python -> Swift, via stdout)

| Event | Meaning |
|---|---|
| `status` | Loading progress (`loading_models`, `wake_word_ready`, `whisper_ready`) |
| `idle` | Engine initialized or dictation stopped — waiting for activation |
| `ready` | Dictation active, waiting for speech |
| `speech_start` | Audio level crossed silence threshold — user is speaking |
| `transcribing` | Processing a batch of speech |
| `transcription` | Result with `text` field — triggers paste |
| `language_detected` | Which language was used for this transcription |
| `wake_word_cancel` | Wake word said during dictation — current batch discarded, stays in dictation |
| `warning` | Non-fatal issue (e.g. audio device changed) |
| `error` | Something went wrong |

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
| **Cancelled** | `wake_word_cancel` | Shaking bars, red (1s) | Shaking bars + "Cancelled" (1s) | Wake word cancelled current batch |
| **Error** | `error` | Error icon | Hidden | Something failed |

After transcription completes, the engine returns to **Ready** if still dictating. The **Cancelled** state is a 1-second visual indicator triggered by the wake word — it overlays on top of the current state and returns to **Ready** automatically.

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
| `Settings.swift` | `AppSettings` (UserDefaults-backed), `WhisperLanguage` catalog with flags |
| `SettingsView.swift` | Grouped form with language chips, searchable language list, overlay toggle |

## Menu Bar

The menu dynamically updates via `NSMenuDelegate`:

- **Start Dictating / Stop Dictating** — toggles dictation (changes label based on state)
- **Last Transcriptions** — up to 5 recent transcriptions; clicking one pastes it into the active app
- **Settings...** — opens the settings window
- **About Overhear** — standard macOS about panel
- **Quit Overhear**

## Python Engine — Key Decisions

- **Audio capture**: `sounddevice` with 16kHz mono float32, 1280-sample chunks (80ms — what openwakeword expects).
- **Audio device recovery**: The audio stream is wrapped in a retry loop. When the default input device changes (e.g. AirPods connecting), the stream re-opens automatically after a 1-second delay.
- **Wake word**: Audio is converted to int16 before passing to openwakeword (it expects int16, not float32). Detection threshold is 0.5. During dictation, the wake word cancels the current batch (both during recording and after transcription) but does not stop dictation.
- **Dictation mode**: Records in batches — accumulates chunks until 1.5s of silence, then transcribes that batch and keeps listening. Activated/deactivated via commands from the Swift host.
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
