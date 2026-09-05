import Combine
import Foundation

/// Owns the engine and translates its events into app state.
///
/// The seam between the engine and the UI: everything above it deals in
/// `AppState` and a start/activate/deactivate/stop surface, and never touches an
/// audio buffer or a model.
@MainActor
final class EngineController {
    private let appState: AppState
    private let injector: TextInjecting
    private let modelsDirectory: URL

    /// How to build the engine's microphone. A closure rather than a single
    /// instance because each restart gets a fresh engine, and a capture that
    /// has already been stopped cannot be reused.
    private let makeAudioSource: @Sendable () -> any AudioSource

    /// How to build a transcriber for a model. A closure because activating
    /// another model means loading different weights, which is a new
    /// transcriber rather than a swap inside the existing one.
    private let makeTranscriber: @Sendable (TranscriptionModel) -> any Transcribing

    /// Kept across restarts. Changing a language or the cancel word rebuilds
    /// the engine, and reloading Whisper each time would turn a settings toggle
    /// into a multi-second stall for no reason — the model does not depend on
    /// either setting. Changing the model is the one thing that does replace it.
    private var transcriber: (any Transcribing)?
    private var loadedModelID: String?

    private let settings: AppSettings

    private var engine: DictationEngine?
    private var listener: Task<Void, Never>?
    private var translationObservation: AnyCancellable?

    init(appState: AppState,
         injector: TextInjecting = PasteboardTextInjector(),
         modelsDirectory: URL = HotWord.modelsDirectory,
         makeTranscriber: @escaping @Sendable (TranscriptionModel) -> any Transcribing = { TranscriberFactory.make(for: $0) },
         makeAudioSource: @escaping @Sendable () -> any AudioSource = { AudioCapture() },
         settings: AppSettings? = nil) {
        self.appState = appState
        self.injector = injector
        self.modelsDirectory = modelsDirectory
        self.makeTranscriber = makeTranscriber
        self.makeAudioSource = makeAudioSource
        // Resolved here rather than as a default argument: `AppSettings.shared`
        // is main actor isolated and a default argument is not.
        self.settings = settings ?? .shared
    }

    func start() {
        // An engine that failed to load is still an engine, and this guard
        // would turn every later attempt into a no-op — including the one
        // `AppDelegate` makes once the wake word models it was missing have
        // arrived. So a failed engine is replaced rather than kept.
        //
        // Torn down rather than reused: the engine gives up at the first load
        // failure and never retries on its own. Immediately, with none of the
        // pause a restart takes, because it returns before starting the pump —
        // a load that failed never reached the microphone, so there is nothing
        // to wind down before the next one opens it.
        if engine != nil, appState.status == .error {
            stop()
        }

        guard engine == nil else { return }

        appState.status = .loading
        appState.errorMessage = nil

        let engine = DictationEngine(
            capture: makeAudioSource(),
            transcriber: transcriberForActiveModel(),
            modelsDirectory: modelsDirectory
        )
        self.engine = engine

        // Sorted, not just converted: `selectedLanguageCodes` is a Set, whose
        // iteration order changes between launches, and the engine's
        // single-language shortcut and detection fallback both depend on the
        // order it is given.
        let languages = settings.effectiveLanguageCodes.sorted()
        let cancelWordPath = settings.cancelWord.modelPath(in: modelsDirectory)

        // Pushed in rather than passed to start(...): it applies to the next
        // batch, where a language change rebuilds the engine.
        let translates = settings.translateUnsupported
        translationObservation = settings.$translateUnsupported
            .sink { value in
                Task { await engine.setTranslatesUnsupported(value) }
            }

        listener = Task { [weak self] in
            let events = await engine.events()
            await engine.setTranslatesUnsupported(translates)
            await engine.start(languages: languages, cancelWordPath: cancelWordPath)
            for await event in events {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    /// The transcriber for whichever model is active, built anew when that is
    /// not the model already loaded.
    private func transcriberForActiveModel() -> any Transcribing {
        let model = settings.activeModel
        if let transcriber, loadedModelID == model.id {
            return transcriber
        }
        let fresh = makeTranscriber(model)
        transcriber = fresh
        loadedModelID = model.id
        return fresh
    }

    func activate() {
        Task { await engine?.activate() }
    }

    func deactivate() {
        Task { await engine?.deactivate() }
    }

    func stop() {
        appState.status = .stopped
        appState.errorMessage = nil

        listener?.cancel()
        listener = nil
        translationObservation = nil

        let engine = self.engine
        self.engine = nil
        Task { await engine?.stop() }
    }

    private func handle(_ event: EngineEvent) {
        switch event {
        case .status:
            appState.status = .loading

        case .idle:
            appState.status = .idle

        case .ready:
            appState.status = .ready

        case .speechStart:
            appState.status = .listening

        case .transcribing:
            appState.status = .transcribing

        case .transcription(let text):
            // Whisper describes non-speech rather than transcribing it, and in a
            // dictation app that description would be pasted into the user's
            // document. Filtered here rather than in the engine so the setting
            // takes effect immediately instead of on the next engine restart.
            let filter = AnnotationFilter(stripsParentheses: settings.stripAnnotations)
            let spoken = filter.filter(text)
            guard !spoken.isEmpty else { break }
            appState.addTranscription(spoken)
            injector.inject(text: spoken)

        case .wakeWordCancel:
            appState.status = .ready
            appState.triggerCancelled()

        case .error(let message):
            appState.status = .error
            appState.errorMessage = message

        case .languageDetected, .warning:
            break
        }
    }
}
