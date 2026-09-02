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
|       └── WhisperTranscriber ....... WhisperKit or FluidAudio        |
+-------------------------------------------------------------+
```

### The seam

`EngineEvent` is the whole contract between the engine and the UI. Everything above `EngineController` — `AppState`, the overlay, the menu bar icon — is driven by those cases alone and never touches an audio buffer or a model. Everything below is free to change how it captures or infers without the UI noticing.

That boundary is also what makes the engine testable: `DictationEngineTests` drives the loop through a scripted `AudioSource` and asserts on the events that come out.

## Dependencies

| Package | Used for |
|---|---|
| [argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) (`WhisperKit`) | Whisper transcription on CoreML |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Parakeet transcription on CoreML |
| [onnxruntime-swift-package-manager](https://github.com/microsoft/onnxruntime-swift-package-manager) | Running openWakeWord's `.onnx` models |
| [SwiftLintPlugins](https://github.com/SimplyDanny/SwiftLintPlugins) | Linting |

ONNX Runtime links statically, so the built `.app` is three files: the binary, `Info.plist` and the icon.

## Engine Events

`DictationEngine` publishes an `AsyncStream<EngineEvent>`; `EngineController` consumes it and maps each case onto `AppState`.

| Event | Meaning |
|---|---|
| `status` | Loading progress (`loading_models`, `wake_word_ready`, `transcriber_ready`) |
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
| `Engine/Transcribing.swift` | The engine seam: `Transcription`, `Transcribing`, and the factory that picks an engine |
| `Engine/WhisperTranscriber.swift` | WhisperKit: model loading, language detection, transcription |
| `Engine/ParakeetTranscriber.swift` | FluidAudio: model loading, transcription, the language check |
| `Engine/ParakeetVariant.swift` | The one place that knows FluidAudio's names for the models offered |
| `Engine/AnnotationFilter.swift` | Strips Whisper's non-speech annotations from a transcription |
| `Engine/DecodePolicy.swift` | Chooses the language and task Whisper decodes a batch with |
| `Engine/LanguageDetector.swift` | Scores every language in one detection pass, so the user's can be ranked |
| `Engine/ModelSetup.swift` | Downloads the wake word models on first launch |
| `Engine/EngineEvent.swift` | The event vocabulary and engine errors |
| `SetupWindow.swift` | First-launch setup window — progress, failure detail, Try Again |
| `Permissions.swift` | Microphone and Accessibility state, asking for them, and watching for grants made in System Settings |
| `PermissionsWindow.swift` | Launch-time permissions window — one explanation and one button per permission |
| `OverlayWindow.swift` | Floating status window (top-right corner) |
| `MenuBarIcon.swift` | SwiftUI view embedded in NSStatusItem |
| `TextInjector.swift` | Pastes transcribed text via pasteboard + simulated Cmd+V, restores previous clipboard |
| `Settings.swift` | `AppSettings` (UserDefaults-backed), `WhisperLanguage` catalog, `HotWord` model |
| `SettingsView.swift` | The General and Hot Words panes |
| `TranscriptionModel.swift` | The model catalogue: engines, variants, sizes, supported languages |
| `TranscriptionModelService.swift` | What is downloaded, downloading, activated and removed |
| `TranscriptionSettingsView.swift` | The Transcription pane: active model, its languages |
| `AvailableModels.swift` | The catalogue half of that pane, grouped by engine |
| `LanguagePicker.swift` | The language multi-select popover |
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

WhisperKit with CoreML, running on the Neural Engine. Which model is up to the user: `ModelCatalog` offers Whisper's tiny, base, base.en, small and large-v3 turbo, and `base` is the default — small, fast and multilingual, the balance dictation wants.

**Two engines.** `Transcribing` is the whole contract: audio in, text and a language out. `TranscriberFactory` picks the implementation from `model.engine`, and `EngineController` rebuilds the transcriber whenever the active model changes. Whisper is told which language to decode and can be asked to translate; Parakeet decides for itself, takes at most a hint, and cannot translate at all — so the translate setting is hidden from the General pane while a Parakeet model is active, rather than left visible and inert.

That difference is why Parakeet checks its own output. The selected languages cannot constrain the decode, so `ParakeetTranscriber` reads the language of the text it produced — `NLLanguageRecognizer`, since `ASRResult` carries no language — and drops a transcription that landed outside the selection. Short or uncertain text is kept: a guess is not grounds for throwing away what someone said. The decoder state is fresh per batch, because batches are separated by a pause and can be discarded whole (a cancel word in the backlog, a stop mid-transcription), and carrying state forward would let cancelled speech condition the next utterance.

**Managing the models.** `TranscriptionModelService` owns what is on disk. Each engine gets a directory beneath Application Support — `whisper/` and `parakeet/` — and lays its own tree out inside it, because both libraries default to somewhere unsuitable (`~/Documents/huggingface`, `~/.cache/fluidaudio`). What counts as downloaded is asked of the engine: a compiled `.mlmodelc` for Whisper, and for Parakeet `AsrModels.modelsExist`, because a Parakeet model is four bundles plus a separately-fetched vocabulary and "contains something compiled" would call it finished as soon as the first bundle landed. A download that cancels, fails, or finishes incomplete deletes its folder rather than leaving something that looks like a model and cannot load. Downloads run per model with progress, so several can run at once and dictation continues on the model already loaded throughout — the service never loads a model, it only writes files and the `activeTranscriptionModel` setting.

Activating is therefore just that setting changing. `AppDelegate` observes it and reloads the engine at once rather than on the restart debounce, since activating is one deliberate click rather than the three ticks a language change can be. Stopping the engine first is what discards the audio dictated so far: the event listener goes with it, so a batch that was mid-transcription cannot arrive and be pasted against the model that has just been swapped out. Dictation resumes afterwards if it was running.

`EngineController` keeps its transcriber across restarts and replaces it only when the active model changes — reloading weights for a language toggle would turn a settings change into a multi-second stall.

**Models and languages.** A model that is not multilingual constrains what can be recognised, so the language selection lives with the model in the Transcription pane rather than in a pane of its own. The selection is never edited by that constraint: `selectedLanguageCodes` stays whatever the user picked and `effectiveLanguageCodes` — what the engine is given — is that set narrowed to what the active model supports. Activating `base.en` with English and Polish selected makes Polish inert rather than forgetting it, and activating a multilingual model brings it back. The picker dims unsupported languages in place for the same reason.

**Non-speech annotations.** Given a cough or a pause, Whisper describes the sound rather than transcribing speech — `[ Pause ]`, `[BLANK_AUDIO]`, `(coughing)` — and in a dictation app that description is pasted into the user's document. Whisper has two defences against this and neither is usable here: `DecodingOptions.supressTokens` defaults to empty, with the call that would fill it left as `// nonSpeechTokens() // TODO`, and that function does not exist in the package; and every segment's `noSpeechProb` is hardcoded to `0`, so `noSpeechThreshold` can never fire. So `AnnotationFilter` strips the annotations from the text instead. Square brackets and musical notes go unconditionally — nobody dictates them — while parentheses are governed by a setting, since a speaker could plausibly produce one. It runs in `EngineController` rather than `WhisperTranscriber` so the setting applies without restarting the engine.

**Language detection and the decode plan.** Whisper is never asked to translate — the task has always been `.transcribe` — but the decoder is prefilled with a language token, and `options.language ?? Constants.defaultLanguageCode` makes that token `<|en|>` whenever no language is given. Telling Whisper that Polish audio is English makes it render the speech as English, which to a user is indistinguishable from the app translating behind their back. Choosing that token is therefore the whole game, and `DecodePolicy` owns the choice:

| Detected | Translate setting off | on |
|---|---|---|
| A selected language | Transcribe in that language | Transcribe in that language |
| Anything else | Transcribe in the detected language | Translate to English |

The selected languages are authoritative: output stays inside them unless translation is deliberately turned on. What makes that safe is that the choice *among* them is the model's, not a fixed rule. Two earlier versions used a fixed rule and both produced R-98's symptom — falling back to the alphabetically first selected language turned every misdetection into English, and skipping detection when only one language was selected turned all foreign speech into that language.

Ranking the user's languages needs a score for each, and `WhisperKit.detectLangauge` reports only the one it sampled. `LanguageDetector` therefore repeats what that method does — pad, mel, encode, one decoder step — but hands `textDecoder.detectLanguage` a `TokenSampling` implementation that reads the whole language row of the logits on the way past. Same single inference, ninety-nine scores instead of one. On the `base` model a Polish clip scores `pl` at 23.2 against `en` at 15.5, which is the margin that keeps Polish Polish.

The cost is coupling: this calls WhisperKit's encoder and decoder directly rather than its one-line helper, so a future release could require rework. It is confined to `LanguageDetector`.

Translation is English-only. Whisper has a single `<|translate|>` token and no target-language token, so no other destination is possible.

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
| Translate unsupported languages | `translateUnsupportedLanguages` | off | Whether speech in an unselected language is translated to English |
| Recognition languages | `selectedLanguages` | `en`, `pl` | Whisper language set; at least one must be selected |
| Active model | `activeTranscriptionModel` | `whisper-base` | Which model transcribes; stored by catalogue id |

The engine takes its language set, cancel word and model when it starts, so changing any of them restarts it — and the model change reloads the weights with it. The annotation and translation settings do not: both are read per batch, so they apply live. `AppDelegate` observes both and calls `scheduleRestart()`, which debounces for 1 second — so toggling several languages in a row produces a single restart rather than one per toggle. Whisper stays loaded across a restart: neither setting affects the model, and reloading it would turn a settings toggle into a multi-second stall. The overlay and launch toggles apply live and never restart the engine.

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

`swift test` runs the suite. The scenarios come from `Specs/`, and the audio they name is loaded from `Specs/Fixtures/Synthetic` through `SyntheticSample`, so a spec and the test that covers it are hearing the same recording. The interesting parts:

- `WakeWordDetectorTests` — the golden test for the openWakeWord port, asserting against scores measured from openWakeWord's own implementation, and that each word model hears only its own phrase.
- `DictationEngineTests` — drives the loop with a scripted audio source and real wake word models: batching, the thirty-second cap, silence and levels below the speech threshold, the stop rules, and losing and regaining the microphone.
- `CancelWordTests` — `Specs/CancelWord.md` against the same harness, covering all three places the word can land: mid-utterance, at the end of one, and in the backlog that piles up while Whisper is running.
- `EngineControllerTests` — engine events reaching `AppState` and the pasteboard, the layer the menu bar and overlay render from, including the settings that apply without rebuilding the engine.
- `AnnotationFilterTests` — that Whisper's descriptions of non-speech never reach the document, using the strings from the bug report.
- `DecodePolicyTests` — the table above, including that a misdetected language is never forced to English.
- `ChunkAccumulatorTests` — that no sample is lost or duplicated across awkward buffer boundaries.
- `WhisperTranscriberTests` — real WhisperKit, opt-in via `OVERHEAR_RUN_MODEL_TESTS=1` because it downloads model weights: the language scenarios from `Specs/Languages.md`, and what a cough comes back as.
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
