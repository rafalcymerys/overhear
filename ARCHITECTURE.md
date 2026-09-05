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
|       └── Transcribing ...... WhisperKit or FluidAudio       |
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

ONNX Runtime links statically, so the built `.app` is the binary, `Info.plist`, the icon, and the resource bundles SwiftPM produces for targets that carry resources — including Overhear's own, which holds the generated `Acknowledgements.txt`.

Every package above except SwiftLintPlugins ships inside the app, so its license text has to ship too. `Resources/acknowledgements.json` records which resolved packages ship and which are build-time only; the `GenerateAcknowledgements` build plugin reconciles that file against the resolved graph on every build and fails with a diagnostic when the two disagree, so adding a dependency without classifying it breaks the build rather than quietly shipping an incomplete notice. See [Licensing](#licensing).

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

The source is laid out by feature, matching the way `Specs/` divides the
behaviour — a spec has one obvious place to land.

### `App/`

| File | Role |
|---|---|
| `OverhearApp.swift` | App entry point, accessory (no dock icon) |
| `AppDelegate.swift` | Menu bar setup, setup gate, wake word fetch, engine lifecycle, settings observation |
| `AppState.swift` | Observable state enum: stopped, loading, idle, ready, listening, transcribing, error |
| `AboutWindow.swift` | The About window and the build's name, version and copyright |
| `AcknowledgementsWindow.swift` | Scrolling window over the bundled third-party license notice |
| `Acknowledgements.swift` | Reads the generated notice out of the bundle |

### `Engine/`

| File | Role |
|---|---|
| `EngineController.swift` | Owns the engine, maps its events onto `AppState`, injects text |
| `DictationEngine.swift` | The dictation loop: batching, cancel word, stop rules |
| `AudioCapture.swift` | `AVAudioEngine` capture, resampling, device-loss recovery |
| `ChunkAccumulator.swift` | Re-slices arbitrary buffers into exact 1280-sample chunks |
| `EngineEvent.swift` | The event vocabulary and engine errors |

### `Engine/Transcribers/`

| File | Role |
|---|---|
| `Transcribing.swift` | The engine seam: `Transcription`, `Transcribing`, and the factory that picks an engine |
| `WhisperTranscriber.swift` | WhisperKit: model loading, language detection, transcription |
| `ParakeetTranscriber.swift` | FluidAudio: model loading, transcription, the language check |
| `ParakeetVariant.swift` | The one place that knows FluidAudio's names for the models offered |
| `DecodePolicy.swift` | Chooses the language and task Whisper decodes a batch with |
| `LanguageDetector.swift` | Scores every language in one detection pass, so the user's can be ranked |
| `AnnotationFilter.swift` | Strips a model's descriptions of non-speech from a transcription |

### `Engine/WakeWord/`

| File | Role |
|---|---|
| `WakeWordDetector.swift` | openWakeWord's three-stage inference, in Swift |
| `ONNXModel.swift` | Thin wrapper over one ONNX Runtime session |
| `WakeWordSetup.swift` | Downloads the wake word models, as a step in the setup window |

### `Models/`

| File | Role |
|---|---|
| `TranscriptionModel.swift` | What a model is: its engine, variant, size and supported languages |
| `ModelCatalog.swift` | Every model offered, and which one is the default |
| `TranscriptionModelService.swift` | What is downloaded, downloading, activated and removed |

### `HotWords/`

| File | Role |
|---|---|
| `HotWord.swift` | A cancel word: the four built in, and custom ones by path |
| `HotWordService.swift` | Discovers, installs (file or URL), and removes custom `.onnx` cancel word models |
| `HotWord+Models.swift` | Resolves a hot word to the file its model lives in |

### `Permissions/`

| File | Role |
|---|---|
| `Permissions.swift` | Microphone and Accessibility state, asking for them, and watching for grants made in System Settings |

### `Setup/`

| File | Role |
|---|---|
| `SetupRequirement.swift` | The four things dictation needs: a model, the wake word models, the microphone, inserting text |
| `SetupCoordinator.swift` | Which requirements are met, which card is open, and the action each offers |
| `SetupWindow.swift` | The window that carries them, and the polling while it is up |
| `SetupView.swift` | The cards it draws |

### `Settings/`

| File | Role |
|---|---|
| `AppSettings.swift` | Every preference, backed by `UserDefaults` |
| `RecognitionLanguage.swift` | The languages that can be selected, with their codes and flags |
| `SettingsWindow.swift` | The window and its toolbar of panes |
| `GeneralSettingsView.swift` | The General pane |
| `HotWordSettingsView.swift` | The Hot Words pane |
| `TranscriptionSettingsView.swift` | The Transcription pane: active model, its languages, translation |
| `AvailableModels.swift` | The catalogue half of that pane, grouped by engine |
| `LanguagePicker.swift` | The language multi-select popover |

### `StatusDisplay/`

| File | Role |
|---|---|
| `MenuBarIcon.swift` | SwiftUI view embedded in NSStatusItem |
| `LiveMark.swift` | The animated mark the icon and overlay share |
| `OverlayWindow.swift` | The floating status window (top-right corner) and where it sits |
| `OverlayView.swift` | What that window draws |

### Top level

| File | Role |
|---|---|
| `TextInjector.swift` | Pastes transcribed text via pasteboard + simulated Cmd+V, restores previous clipboard |
| `ByteCountFormatter+Sizes.swift` | The one formatter every size in the interface goes through |

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

They are **downloaded on first launch rather than shipped inside the app**, which is a licensing decision, not a size one. openWakeWord's pre-trained word models are CC BY-NC-SA 4.0 — only the melspectrogram and Google embedding models are Apache 2.0 — so bundling them would attach those terms to a distribution of Overhear itself. `WakeWordSetup` fetches them from openWakeWord's own release assets.

Custom models can be added in Settings, either from a local `.onnx` file or by URL. They land in the same directory, `~/Library/Application Support/Overhear/models/`, and `HotWordService` lists every `.onnx` file there at launch. The display name is derived from the filename — `my_word.onnx` becomes "My Word". Removing a custom word deletes the file; if it was the selected cancel word, the selection falls back to Alexa.

Built-in words are stored in settings by name (`alexa`) so the stored value stays readable; `HotWord.modelPath` resolves that to the downloaded file. Custom words already carry an absolute path and are used as-is.

## Permissions Required

- **Microphone**: the engine captures audio to hear the cancel word and the dictation itself.
- **Accessibility**: needed for CGEvent-based Cmd+V paste simulation (System Settings > Privacy > Accessibility). Called "inserting text in your apps" in the UI, because that is what it buys the user.

Both are asked for in the setup window, alongside the transcription model — see **Setup** below.

`PermissionsService` decides what a button does, since macOS shows its own dialog only while the answer is still open — and only once per launch:

| State | Button |
|---|---|
| Never answered, not yet asked this launch | Trigger the macOS dialog |
| Already asked this launch, or previously denied | Open the relevant System Settings pane |
| Granted | Replaced by a checkmark |

Neither grant arrives as a notification — Accessibility is switched on in System Settings with the app none the wiser, and the microphone switch is just as silent — so the service polls once a second while the setup window is open. Closing the window stops the polling; the state is still refreshed whenever the menu bar menu opens.

## Setup

Four things have to be true before anything can be dictated: a transcription model on disk, the wake word models, the microphone, and the right to paste. `SetupCoordinator` holds that judgement, and `AppDelegate.start()` consults it before the engine exists. When any is missing the setup window goes up and the launch waits on `isComplete`; the menu bar offers **Finish Setup…** in place of **Start Listening** meanwhile.

One window rather than the two that used to appear in sequence. The same window serves a fresh install and a later launch that has lost something, which is why it is a checklist rather than a wizard: the card that is open is whichever requirement is outstanding and topmost, so a return visit for a revoked permission is two ticked lines and one open card.

A running download is deliberately skipped when choosing which card to open. It keeps its own card expanded to show progress, and the next requirement opens beneath it — the slow step and the permissions proceed at once, which a wizard could not do.

Nothing is fetched unasked. A fresh install preselects Whisper Base and waits for **Download**; an install whose active model has lost its files preselects that model rather than the default, and still waits. `SetupCoordinator.download()` activates only once the bytes have landed, so a cancelled or failed download leaves nothing loaded that isn't there.

The wake word models are the one card that asks for nothing. Nobody chooses them, so `SetupCoordinator` starts `WakeWordSetup.startDownload()` as soon as it exists and the card comes up already downloading — its progress is a fraction of the files this run has to fetch, since the fetch reports nothing finer than a finished file. A failure stays on the card with a **Try Again** rather than reaching the menu bar, and is not retried by a refresh: reopening the window or the menu must not quietly start it over.

Because they are a requirement, setup finishing and the engine starting are not separated by a download. `AppDelegate.startEngine()` runs with everything the engine loads already on disk, which is why `reloadModel()` only has to guard against an engine that does not exist yet rather than one racing a fetch.

## Testing

`swift test` runs the suite. `Tests/OverhearTests/` mirrors the source layout, so a file and the tests that cover it sit at the same path under each — with `Support/` holding the harnesses and fakes the suites share. The scenarios come from `Specs/`, and the audio they name is loaded from `Specs/Fixtures/Synthetic` through `SyntheticSample`, so a spec and the test that covers it are hearing the same recording. The interesting parts:

- `WakeWordDetectorTests` — the golden test for the openWakeWord port, asserting against scores measured from openWakeWord's own implementation, and that each word model hears only its own phrase.
- `DictationEngineTests` — drives the loop with a scripted audio source and real wake word models: batching, the thirty-second cap, silence and levels below the speech threshold, the stop rules, and losing and regaining the microphone.
- `CancelWordTests` — `Specs/CancelWord.md` against the same harness, covering all three places the word can land: mid-utterance, at the end of one, and in the backlog that piles up while Whisper is running.
- `EngineControllerTests` — engine events reaching `AppState` and the pasteboard, the layer the menu bar and overlay render from, including the settings that apply without rebuilding the engine.
- `AnnotationFilterTests` — that Whisper's descriptions of non-speech never reach the document, using the strings from the bug report.
- `DecodePolicyTests` — the table above, including that a misdetected language is never forced to English.
- `ChunkAccumulatorTests` — that no sample is lost or duplicated across awkward buffer boundaries.
- `WhisperTranscriberTests` — real WhisperKit, opt-in via `OVERHEAR_RUN_MODEL_TESTS=1` because it downloads model weights: the language scenarios from `Specs/Languages.md`, and what a cough comes back as.
- `AudioCaptureTests` — the real microphone, opt-in via `OVERHEAR_RUN_AUDIO_TESTS=1` because CI has no input device.

## Licensing

Overhear is MIT. Every package it links is MIT or Apache-2.0, and both licenses require their text to travel with a binary distribution, so `Acknowledgements.txt` is generated into the app at build time rather than maintained by hand:

- `Resources/acknowledgements.json` — which resolved packages ship, and why the others don't.
- `Resources/acknowledgements-preamble.txt` — the hand-written part: Overhear's own terms, and credit for the transcription and wake word models, which are downloaded on demand rather than bundled.
- `Plugins/GenerateAcknowledgements` — reconciles the manifest against the resolved graph, then drives the script below. Errors on an unclassified package, a stale entry, or a shipping package with no license file.
- `scripts/generate-acknowledgements.sh` — concatenates each package's `LICENSE*` and `NOTICE*` under the preamble.

Because it runs as a build tool plugin, `swift build`, `swift test` and `scripts/build.sh` all produce the same file and read it the same way, through `Bundle.module`. Nothing generated is committed.

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
