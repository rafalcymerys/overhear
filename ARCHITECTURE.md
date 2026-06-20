# Overhear — Architecture

A macOS menu bar app for hands-free dictation. Say a wake word, speak naturally, and your words are transcribed and pasted into whatever text field is active.

## Core Concept

Overhear runs silently in the background, listening for a wake word ("hey jarvis" by default). Once activated, it enters **dictation mode**: it continuously captures speech in batches, transcribes each batch when you pause, and injects the text into the focused application. Saying the wake word again (or pressing stop) deactivates dictation.

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
{"command": "quit"}
{"command": "activate"}
{"command": "deactivate"}
```

### Events (Python -> Swift, via stdout)

| Event | Meaning |
|---|---|
| `status` | Loading progress (`loading_models`, `wake_word_ready`, `whisper_ready`) |
| `ready` | Engine fully initialized |
| `listening` | Idle, waiting for wake word |
| `wake_word` | Wake word detected (includes model name, score) |
| `dictating` | In dictation mode, ready for speech |
| `speech_start` | Audio level crossed silence threshold — user is speaking |
| `transcribing` | Processing a batch of speech |
| `transcription` | Result with `text` field — triggers paste |
| `language_detected` | Which language was used for this transcription |
| `wake_word_off` | Wake word said during dictation — toggling off |
| `error` | Something went wrong |

## Swift Host — Key Components

| File | Role |
|---|---|
| `OverhearApp.swift` | App entry point, accessory (no dock icon) |
| `AppDelegate.swift` | Menu bar setup (Settings / Quit menu), engine lifecycle, settings observation |
| `AppState.swift` | Observable state enum: stopped, loading, listening, dictating, hearing, transcribing, error |
| `EngineProcess.swift` | Launches Python subprocess, reads JSON events, dispatches to AppState |
| `OverlayWindow.swift` | Floating status window (top-right corner) — shows Ready/Listening/Transcribing/Result |
| `TextInjector.swift` | Pastes transcribed text via pasteboard + simulated Cmd+V, restores previous clipboard |
| `Settings.swift` | `AppSettings` (UserDefaults-backed), `WhisperLanguage` catalog |
| `SettingsView.swift` | Language selection UI with search and checkboxes |

## Python Engine — Key Decisions

- **Audio capture**: `sounddevice` with 16kHz mono float32, 1280-sample chunks (80ms — what openwakeword expects).
- **Wake word**: Audio is converted to int16 before passing to openwakeword (it expects int16, not float32). Detection threshold is 0.5.
- **Dictation mode**: Records in batches — accumulates chunks until 1.5s of silence, then transcribes that batch and keeps listening. Wake word is checked on every chunk during dictation so it can toggle off.
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
| Ready | Static dot + "Ready" | Black 30% opacity |
| Listening | Animated audio bars + "Listening..." | Frosted material |
| Transcribing | Spinner + "Transcribing..." | Frosted material |
| Result | Transcribed text (5s) | Frosted material |

The overlay appears when dictation activates and hides when it deactivates (or 5s after showing a result, if dictation has already stopped).

## Setup & Dependencies

**Python** (managed via venv):
- `openwakeword` — wake word detection (ONNX models)
- `faster-whisper` — CTranslate2-based Whisper inference
- `sounddevice` — cross-platform audio capture
- `numpy`

**Swift**: No external dependencies. Uses AppKit, SwiftUI, Combine, AVFoundation, Carbon (for key codes).

```bash
./scripts/setup.sh   # creates venv, installs deps, downloads wake word models
swift build           # builds the Swift app
.build/debug/Overhear # run
```

## Permissions Required

- **Microphone**: prompted automatically by macOS on first audio capture
- **Accessibility**: needed for CGEvent-based Cmd+V paste simulation (System Settings > Privacy > Accessibility)
