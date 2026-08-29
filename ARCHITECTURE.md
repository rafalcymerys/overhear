# Overhear — Architecture

A macOS menu bar app for dictation. Click to start listening, speak naturally, and your words are transcribed and pasted into whatever text field is active.

## Core Concept

Overhear runs silently in the menu bar. Clicking **Start Listening** enters dictation mode: the app continuously captures speech in batches, transcribes each batch when you pause, and injects the text into the focused application. Clicking **Stop Listening** (or pressing Stop in the overlay) deactivates dictation. If **Start listening on launch** is enabled (the default), the app activates dictation by itself as soon as the engine finishes loading.

During dictation, saying the **cancel word** — "Alexa" by default — discards whatever is currently being heard or transcribed. The batch is dropped and the app returns to the ready state, still listening for the next utterance. The cancel word is configurable in Settings: four openWakeWord models are offered built in (Alexa, Hey Jarvis, Hey Mycroft, Hey Rhasspy), and additional `.onnx` models can be installed. See [Hot Words](#hot-words).

> Terminology: the feature is called the *cancel word* in the UI, but the underlying models are wake-word detectors, so the event it produces is still named `wakeWordCancel`.

## Architecture: One Native Process

Everything runs in a single Swift app. Audio capture, wake word detection and transcription all happen in-process, on Apple frameworks and Swift packages.

```
+-------------------------------------------------------------+
|                      Overhear (Swift)                        |
|                                                              |
|  AppDelegate ── menu bar, permissions, engine lifecycle      |
|       │                                                      |
|  EngineController ── engine events → AppState → paste        |
|       │                                                      |
|  DictationEngine (actor) ── batching, cancel, stop rules     |
|       ├── AudioCapture ...... AVAudioEngine, 16kHz mono      |
|       ├── WakeWordDetector .. openWakeWord models on ORT     |
|       └── Transcriber ....... WhisperKit (CoreML Whisper)    |
+-------------------------------------------------------------+
```

### The seam

`EngineEvent` is the whole contract between the engine and the UI. Everything above `EngineController` — `AppState`, the overlay, the menu bar icon — is driven by those cases alone and never touches an audio buffer or a model. Everything below is free to change how it captures or infers without the UI noticing.

That boundary is also what makes the engine testable: `DictationEngineTests` drives the loop through a scripted `AudioSource` and asserts on the events that come out.

## Dependencies

| Package | Used for |
|---|---|
| [argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) (`WhisperKit`) | Whisper transcription on CoreML |
| [onnxruntime-swift-package-manager](https://github.com/microsoft/onnxruntime-swift-package-manager) | Running openWakeWord's `.onnx` models |
| [SwiftLintPlugins](https://github.com/SimplyDanny/SwiftLintPlugins) | Linting |

ONNX Runtime links statically, so the built `.app` is three files: the binary, `Info.plist` and the icon.

## Engine Events

`DictationEngine` publishes an `AsyncStream<EngineEvent>`; `EngineController` consumes it and maps each case onto `AppState`.

| Event | Meaning |
|---|---|
| `status` | Loading progress (`loading_models`, `wake_word_ready`, `whisper_ready`) |
| `idle` | Engine initialized or dictation stopped — waiting for activation |
| `ready` | Dictation active, waiting for speech |
| `speechStart` | Audio level crossed the silence threshold — user is speaking |
| `transcribing` | Processing a batch of speech |
| `transcription` | Result — triggers paste |
| `languageDetected` | Which language was used for this transcription |
| `wakeWordCancel` | Cancel word said during dictation — current batch discarded, stays in dictation |
| `warning` | Non-fatal issue (e.g. audio device changed) |
| `error` | Something went wrong |

`languageDetected` carries no UI behaviour today; it is emitted for diagnostics and ignored by the controller.

## Engine States

The engine and UI share a unified state model:

| State | Engine event | Menu bar | Overlay | Description |
|---|---|---|---|---|
| **Stopped** | — | Mic icon | Hidden | App not started |
| **Loading** | `status` | Mic icon | Hidden | Loading ML models |
| **Idle** | `idle` | Mic icon | Hidden | Ready to be activated via menu |
| **Ready** | `ready` | Static bars, orange | "Ready" (dark bg) | Dictation active, waiting for speech |
| **Listening** | `speechStart` | Animated bars, orange | "Listening..." (material bg) | Actively hearing speech |
| **Transcribing** | `transcribing` | Spinner, dark orange | "Transcribing..." (material bg) | Processing with Whisper |
| **Cancelled** | `wakeWordCancel` | Shaking bars, red (1s) | Shaking bars + "Cancelled" (1s) | Cancel word discarded current batch |
| **Error** | `error` | Error icon | Hidden | Something failed |

After transcription completes, the engine returns to **Ready** if still dictating. The **Cancelled** state is a 1-second visual indicator triggered by the cancel word — it overlays on top of the current state and returns to **Ready** automatically.

## Key Components

| File | Role |
|---|---|
| `OverhearApp.swift` | App entry point, accessory (no dock icon) |
| `AppDelegate.swift` | Menu bar setup, permission gate, model setup, engine lifecycle, settings observation |
| `AppState.swift` | Observable state enum: stopped, installing, loading, idle, ready, listening, transcribing, error |
| `Engine/EngineController.swift` | Owns the engine, maps its events onto `AppState`, injects text |
| `Engine/DictationEngine.swift` | The dictation loop: batching, cancel word, stop rules |
| `Engine/AudioCapture.swift` | `AVAudioEngine` capture, resampling, device-loss recovery |
| `Engine/ChunkAccumulator.swift` | Re-slices arbitrary buffers into exact 1280-sample chunks |
| `Engine/WakeWordDetector.swift` | openWakeWord's three-stage inference, in Swift |
| `Engine/ONNXModel.swift` | Thin wrapper over one ONNX Runtime session |
| `Engine/Transcriber.swift` | WhisperKit: model loading, language detection, transcription |
| `Engine/AnnotationFilter.swift` | Strips Whisper's non-speech annotations from a transcription |
| `Engine/ModelSetup.swift` | Downloads the wake word models on first launch |
| `Engine/EngineEvent.swift` | The event vocabulary and engine errors |
| `SetupWindow.swift` | First-launch setup window — progress, failure detail, Try Again |
| `Permissions.swift` | Microphone and Accessibility state, asking for them, and watching for grants made in System Settings |
| `PermissionsWindow.swift` | Launch-time permissions window — one explanation and one button per permission |
| `OverlayWindow.swift` | Floating status window (top-right corner) |
| `MenuBarIcon.swift` | SwiftUI view embedded in NSStatusItem |
| `TextInjector.swift` | Pastes transcribed text via pasteboard + simulated Cmd+V, restores previous clipboard |
| `Settings.swift` | `AppSettings` (UserDefaults-backed), `WhisperLanguage` catalog, `HotWord` model |
| `SettingsView.swift` | Grouped form with language chips, toggles, hot word management |
| `HotWordService.swift` | Discovers, installs (file or URL), and removes custom `.onnx` cancel word models |

## Audio Capture

`AVAudioEngine` taps the default input, and an `AVAudioConverter` resamples whatever the device produces to 16 kHz mono float32. The device chooses its own buffer size and it is never the 1280 samples the models want, so `ChunkAccumulator` holds the remainder between buffers and emits only whole chunks — dropping the remainder instead would punch a silent gap into the audio every few frames, which reads to the detector as a word cut in half.

Recovery covers two distinct failures:

- The stream fails **to open** — no input device, device busy. Capture emits `.interrupted` and retries every second until it succeeds.
- An open stream **stops delivering**. More than `timeout` (3s) without a single buffer is treated as a lost device: the tap is torn down and the stream reopened. Audio arrives every few tens of milliseconds on a healthy stream even during silence, so the margin is wide.

`AVAudioEngineConfigurationChange` also fires when the device is swapped, and shortcuts the watchdog rather than replacing it: a device that simply stops producing — a sleeping USB interface, a virtual device whose host quit — never posts one.

Dictation does not survive either case: the engine returns to idle and the user starts again.

## Wake Word Detection

`WakeWordDetector` is a port of openWakeWord's streaming inference, running the same `.onnx` files. Three graphs in sequence, per 1280-sample chunk:

1. `melspectrogram.onnx` — the chunk plus three hops of history (1760 samples) becomes 8 mel frames of 32 bins, transformed by `x/10 + 2` to match the range the next model was trained against.
2. `embedding_model.onnx` — Google's `speech_embedding`, turning the last 76 mel frames into a 96-value vector.
3. The per-word head — the last 16 of those vectors become one score. Above 0.5 is a detection.

Only the third stage is per-word, which is why a custom model is a few hundred kilobytes rather than a whole network. The tensor names of the word heads differ between models (`onnx::Flatten_0` in alexa, `x.1` in hey_jarvis), so `ONNXModel` reads them off the session instead of hardcoding.

The buffering mirrors `AudioFeatures._streaming_features` in openWakeWord frame for frame, including seeding the feature buffer with embeddings of four seconds of noise on reset — without it the first sixteen frames after a reset are scored against zeros, far outside anything the head saw in training. `WakeWordDetectorTests` pins the port to scores measured by running openWakeWord's own implementation over the same clips: 0.999999 for "alexa", 0.000328 for unrelated speech. It matches both to within 0.0001.

## Dictation Loop

`DictationEngine` is an actor running two tasks: a pump that drains `AudioCapture` into a queue, and the loop that consumes it. They are separate because the recorder spends most of its life waiting on that queue — if it were also the thing feeding it, nothing would ever arrive.

- **Batching.** Chunks accumulate until 1.5s of silence, then that batch is transcribed and listening continues. Batches are capped at 30s. A batch in which the level never crossed the silence threshold (0.008 mean absolute amplitude) is discarded without transcribing; there is no minimum-duration filter beyond that, deliberately — Whisper's VAD already yields empty text for non-vocal noise, and real one-word utterances are too close to any workable threshold to cut safely.
- **Cancel word.** Checked in two places: on every chunk while recording, and against the audio that buffered up while Whisper was running, so a cancel spoken during transcription still suppresses the result. If no cancel word is found in that buffered audio, the chunks go back on the queue so the next batch doesn't lose its opening words.
- **Stopping is a hard stop.** An utterance still being recorded is discarded, and a transcription still running when the stop arrives is dropped rather than pasted — nothing reaches the user's document after they press Stop.

## Transcription

WhisperKit's `base` model with CoreML — small, fast and multilingual, running on the Neural Engine.

**Non-speech annotations.** Given a cough or a pause, Whisper describes the sound rather than transcribing speech — `[ Pause ]`, `[BLANK_AUDIO]`, `(coughing)` — and in a dictation app that description is pasted into the user's document. Whisper has two defences against this and neither is usable here: `DecodingOptions.supressTokens` defaults to empty, with the call that would fill it left as `// nonSpeechTokens() // TODO`, and that function does not exist in the package; and every segment's `noSpeechProb` is hardcoded to `0`, so `noSpeechThreshold` can never fire. So `AnnotationFilter` strips the annotations from the text instead. Square brackets and musical notes go unconditionally — nobody dictates them — while parentheses are governed by a setting, since a speaker could plausibly produce one. It runs in `EngineController` rather than `Transcriber` so the setting applies without restarting the engine.

**Language detection** cannot be constrained to the selected set, which is a limit worth knowing about. WhisperKit's `langProbs` carries only the language it sampled: the other entries are absent, and the values it does carry are log probabilities, so a missing entry cannot be defaulted to zero and ranked against the rest. Instead: with one language selected there is no detection at all; with several, Whisper's own answer is used when it is one of the selected languages, and otherwise the alphabetically first selected language is the fallback, so the choice is the same every launch.

## Text Injection

Uses the pasteboard approach rather than CGEvent key simulation or Accessibility API:

1. Save current clipboard contents
2. Copy transcribed text to pasteboard
3. Simulate Cmd+V via CGEvent
4. Restore previous clipboard after 300ms

This works reliably across all macOS apps without requiring Accessibility permissions for the target app.

## Settings

All settings live in `AppSettings.shared`, backed by `UserDefaults` and published via Combine.

| Setting | Key | Default | Effect |
|---|---|---|---|
| Start listening on launch | `dictateOnLaunch` | on | Sends `activate` automatically on the first `idle` after launch |
| Show overlay window while listening | `showOverlay` | on | Whether the floating overlay appears during dictation |
| Cancel word | `cancelWord` | Alexa | Which wake word model cancels the current batch |
| Strip transcription annotations | `stripTranscriptionAnnotations` | on | Whether `(coughing)` and the like are dropped instead of pasted |
| Recognition languages | `selectedLanguages` | `en`, `pl` | Whisper language set; at least one must be selected |

The engine takes its language set and cancel word when it starts, so changing either one restarts it. The annotation setting does not: it is read on every transcription, so it applies live. `AppDelegate` observes both and calls `scheduleRestart()`, which debounces for 1 second — so toggling several languages in a row produces a single restart rather than one per toggle. Whisper stays loaded across a restart: neither setting affects the model, and reloading it would turn a settings toggle into a multi-second stall. The overlay and launch toggles apply live and never restart the engine.

`selectedLanguageCodes` is a `Set`, whose iteration order changes between launches, so `EngineController` sorts it before handing it over — the single-language shortcut and the detection fallback both depend on that order.

## Hot Words

The cancel word is an openWakeWord model. Four are offered built in: Alexa, Hey Jarvis, Hey Mycroft, Hey Rhasspy.

They are **downloaded on first launch rather than shipped inside the app**, which is a licensing decision, not a size one. openWakeWord's pre-trained word models are CC BY-NC-SA 4.0 — only the melspectrogram and Google embedding models are Apache 2.0 — so bundling them would attach those terms to a distribution of Overhear itself. `ModelSetup` fetches them from openWakeWord's own release assets.

Custom models can be added in Settings, either from a local `.onnx` file or by URL. They land in the same directory, `~/Library/Application Support/Overhear/models/`, and `HotWordService` lists every `.onnx` file there at launch. The display name is derived from the filename — `my_word.onnx` becomes "My Word". Removing a custom word deletes the file; if it was the selected cancel word, the selection falls back to Alexa.

Built-in words are stored in settings by name (`alexa`) so the stored value stays readable; `HotWord.modelPath` resolves that to the downloaded file. Custom words already carry an absolute path and are used as-is.

## Permissions Required

- **Microphone**: the engine captures audio to hear the cancel word and the dictation itself.
- **Accessibility**: needed for CGEvent-based Cmd+V paste simulation (System Settings > Privacy > Accessibility). Called "inserting text in your apps" in the UI, because that is what it buys the user.

`AppDelegate.start()` checks both before anything else runs — ahead of the first-launch model download, so a fresh Mac isn't asked to wait for a download that can't lead to working dictation. When either is missing, `PermissionsWindow` explains what each permission is for and offers a button per permission; the launch continues into `bootstrap()` the moment both are granted.

`PermissionsService` decides what a button does, since macOS shows its own dialog only while the answer is still open — and only once per launch:

| State | Button |
|---|---|
| Never answered, not yet asked this launch | Trigger the macOS dialog |
| Already asked this launch, or previously denied | Open the relevant System Settings pane |
| Granted | Replaced by a checkmark |

Neither grant arrives as a notification — Accessibility is switched on in System Settings with the app none the wiser, and the microphone switch is just as silent — so the service polls once a second while the window is open. Closing the window stops the polling; the state is still refreshed whenever the menu bar menu opens, which is also where a **Grant Permissions…** item replaces **Start Listening** until both are in place.

## Testing

`swift test` runs the suite. The interesting parts:

- `WakeWordDetectorTests` — the golden test for the openWakeWord port, asserting against scores measured from openWakeWord's own implementation.
- `DictationEngineTests` — drives the loop with a scripted audio source and real wake word models: batching, silence discarding, cancel-word behaviour, the stop rules, and device loss.
- `EngineControllerTests` — engine events reaching `AppState` and the pasteboard, the layer the menu bar and overlay render from.
- `AnnotationFilterTests` — that Whisper's descriptions of non-speech never reach the document, using the strings from the bug report.
- `ChunkAccumulatorTests` — that no sample is lost or duplicated across awkward buffer boundaries.
- `TranscriberTests` — real WhisperKit, opt-in via `OVERHEAR_RUN_MODEL_TESTS=1` because it downloads model weights.
- `AudioCaptureTests` — the real microphone, opt-in via `OVERHEAR_RUN_AUDIO_TESTS=1` because CI has no input device.

## Linting

SwiftLint is included as an SPM plugin and runs automatically as a pre-commit hook. To lint manually:

```bash
swift package plugin --allow-writing-to-package-directory swiftlint lint
```

## Building

```bash
swift build            # builds the app
.build/debug/Overhear  # run it
./scripts/build.sh     # release .app bundle in dist/
```
