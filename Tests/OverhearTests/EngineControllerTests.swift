import XCTest
@testable import Overhear

/// The last wiring layer: engine events reaching `AppState`, the overlay and
/// the pasteboard. Everything the menu bar and the overlay render is driven
/// from here, so a mismapped event is a visibly wrong app.
@MainActor
final class EngineControllerTests: OverhearTestCase {
    private static var modelsDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("overhear-test-models")
    }

    private actor StubTranscriber: Transcribing {
        private let text: String

        init(text: String = "hello world") {
            self.text = text
        }

        func load() async throws {}
        func transcribe(_ audio: [Float], languages: [String]) async throws -> Transcription {
            Transcription(text: text, language: "en")
        }
    }

    override func setUp() async throws {
        try await super.setUp()
        let setup = ModelSetup(directory: Self.modelsDirectory)
        try await setup.ensureModels()
    }

    func testDrivesStateThroughADictationAndPastesTheResult() async throws {
        let appState = AppState()
        let injector = SpyInjector()
        let audio = ScriptedAudioSource()

        let controller = EngineController(
            appState: appState,
            injector: injector,
            modelsDirectory: Self.modelsDirectory,
            transcriber: StubTranscriber(),
            makeAudioSource: { audio }
        )
        defer { controller.stop() }

        controller.start()
        XCTAssertEqual(appState.status, .loading)

        audio.sendSilence(seconds: 0.2)
        await waitUntil("engine reaches idle") { appState.status == .idle }

        controller.activate()
        await waitUntil("engine is ready") { appState.status == .ready }

        audio.sendSpeech(seconds: 1.0)
        await waitUntil("speech is noticed") { appState.status == .listening }

        audio.sendSilence(seconds: 2.0)
        await waitUntil("text is pasted") { injector.injected == ["hello world"] }
        XCTAssertEqual(appState.recentTranscriptions, ["hello world"], "it should also reach the menu")
    }

    /// A failure to load has to surface — a menu bar app that silently does
    /// nothing is indistinguishable from one that is working.
    func testReportsAMissingModel() async throws {
        let appState = AppState()
        let controller = EngineController(
            appState: appState,
            injector: SpyInjector(),
            modelsDirectory: tempDirectory,
            transcriber: StubTranscriber(),
            makeAudioSource: { ScriptedAudioSource() }
        )
        defer { controller.stop() }

        controller.start()

        await waitUntil("the failure is reported") { appState.status == .error }
        XCTAssertNotNil(appState.errorMessage)
    }

    func testStopReturnsToStopped() async throws {
        let appState = AppState()
        let audio = ScriptedAudioSource()
        let controller = EngineController(
            appState: appState,
            injector: SpyInjector(),
            modelsDirectory: Self.modelsDirectory,
            transcriber: StubTranscriber(),
            makeAudioSource: { audio }
        )

        controller.start()
        audio.sendSilence(seconds: 0.2)
        await waitUntil("engine reaches idle") { appState.status == .idle }

        controller.stop()
        XCTAssertEqual(appState.status, .stopped)
        XCTAssertNil(appState.errorMessage)
    }

    // MARK: - R-97

    /// The bug as reported: with nobody speaking, Whisper described the sound it
    /// heard and the description was pasted into the user's document.
    func testAnnotationOnlyTranscriptionsAreNotPasted() async throws {
        for annotation in ["[ Pause ]", "(coughing) (coughing)", "[BLANK_AUDIO]"] {
            let harness = try await makeHarness(transcribing: annotation)
            defer { harness.controller.stop() }

            try await harness.dictateOneBatch()

            XCTAssertTrue(harness.injector.injected.isEmpty, "\(annotation) should not reach the document")
            XCTAssertTrue(harness.appState.recentTranscriptions.isEmpty, "\(annotation) should not reach the menu")
        }
    }

    /// Speech alongside an annotation keeps the speech.
    func testAnnotationsAreStrippedFromRealSpeech() async throws {
        let harness = try await makeHarness(transcribing: "(coughing) hello world")
        defer { harness.controller.stop() }

        try await harness.dictateOneBatch()
        await waitUntil("text is pasted") { harness.injector.injected == ["hello world"] }
    }

    /// With the setting off a parenthesised annotation counts as speech — that
    /// is what the toggle is for. Brackets are stripped either way.
    func testParenthesesSurviveWhenStrippingIsOff() async throws {
        let harness = try await makeHarness(transcribing: "(coughing) hello world") { $0.stripAnnotations = false }
        defer { harness.controller.stop() }

        try await harness.dictateOneBatch()
        await waitUntil("text is pasted") { harness.injector.injected == ["(coughing) hello world"] }
    }

    // MARK: - Harness

    private struct Harness {
        let controller: EngineController
        let appState: AppState
        let injector: SpyInjector
        let audio: ScriptedAudioSource

        /// Speak, pause, and let the batch run through transcription.
        func dictateOneBatch() async throws {
            audio.sendSpeech(seconds: 1.0)
            audio.sendSilence(seconds: 2.0)
            try await Task.sleep(for: .milliseconds(400))
        }
    }

    private func makeHarness(transcribing text: String,
                             configure: (AppSettings) -> Void = { _ in }) async throws -> Harness {
        let appState = AppState()
        let injector = SpyInjector()
        let audio = ScriptedAudioSource()
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        configure(settings)

        let controller = EngineController(
            appState: appState,
            injector: injector,
            modelsDirectory: Self.modelsDirectory,
            transcriber: StubTranscriber(text: text),
            makeAudioSource: { audio },
            settings: settings
        )

        controller.start()
        audio.sendSilence(seconds: 0.2)
        await waitUntil("engine reaches idle") { appState.status == .idle }
        controller.activate()
        await waitUntil("engine is ready") { appState.status == .ready }

        return Harness(controller: controller, appState: appState, injector: injector, audio: audio)
    }
}
