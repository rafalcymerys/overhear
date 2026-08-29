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
        func load() async throws {}
        func transcribe(_ audio: [Float], languages: [String]) async throws -> Transcription {
            Transcription(text: "hello world", language: "en")
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
}
