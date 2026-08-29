import Foundation

/// Owns the engine and translates its events into app state.
///
/// This is what `EngineProcess` used to be, minus the process: it keeps the
/// same start/activate/deactivate/stop surface the app delegate and the overlay
/// were written against, so moving the engine in-process changed nothing above
/// this line.
@MainActor
final class EngineController {
    private let appState: AppState
    private let injector: TextInjecting
    private let modelsDirectory: URL

    /// How to build the engine's microphone. A closure rather than a single
    /// instance because each restart gets a fresh engine, and a capture that
    /// has already been stopped cannot be reused.
    private let makeAudioSource: @Sendable () -> any AudioSource

    /// Kept across restarts. Changing a language or the cancel word rebuilds
    /// the engine, and reloading Whisper each time would turn a settings toggle
    /// into a multi-second stall for no reason — the model does not depend on
    /// either setting.
    private let transcriber: any Transcribing

    private var engine: DictationEngine?
    private var listener: Task<Void, Never>?

    init(appState: AppState,
         injector: TextInjecting = PasteboardTextInjector(),
         modelsDirectory: URL = HotWord.modelsDirectory,
         transcriber: any Transcribing = Transcriber(),
         makeAudioSource: @escaping @Sendable () -> any AudioSource = { AudioCapture() }) {
        self.appState = appState
        self.injector = injector
        self.modelsDirectory = modelsDirectory
        self.transcriber = transcriber
        self.makeAudioSource = makeAudioSource
    }

    func start() {
        guard engine == nil else { return }

        appState.status = .loading
        appState.errorMessage = nil

        let engine = DictationEngine(
            capture: makeAudioSource(),
            transcriber: transcriber,
            modelsDirectory: modelsDirectory
        )
        self.engine = engine

        // Sorted, not just converted: `selectedLanguageCodes` is a Set, whose
        // iteration order changes between launches, and the engine's
        // single-language shortcut and detection fallback both depend on the
        // order it is given.
        let languages = AppSettings.shared.selectedLanguageCodes.sorted()
        let cancelWordPath = AppSettings.shared.cancelWord.modelPath(in: modelsDirectory)

        listener = Task { [weak self] in
            let events = await engine.events()
            await engine.start(languages: languages, cancelWordPath: cancelWordPath)
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
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

        case .transcription(let text) where !text.isEmpty:
            appState.addTranscription(text)
            injector.inject(text: text)

        case .wakeWordCancel:
            appState.status = .ready
            appState.triggerCancelled()

        case .error(let message):
            appState.status = .error
            appState.errorMessage = message

        case .transcription, .languageDetected, .warning:
            break
        }
    }
}
