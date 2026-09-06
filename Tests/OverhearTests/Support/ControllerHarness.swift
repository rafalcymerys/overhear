import Foundation
import XCTest
@testable import Overhear

/// An `EngineController` over a scripted microphone, with everything it drives
/// captured: the state the menu bar and overlay render, and what reached the
/// document.
///
/// One layer above `EngineHarness`, which stops at the engine. Tests about what
/// the user ends up seeing start here.
@MainActor
struct ControllerHarness {
    let controller: EngineController
    let appState: AppState
    let injector: SpyInjector
    let audio: ScriptedAudioSource
    let settings: AppSettings

    /// Speak, pause, and let the batch run through transcription.
    func dictateOneBatch() async throws {
        audio.sendSpeech(seconds: 1.0)
        audio.sendSilence(seconds: 2.0)
        try await Task.sleep(for: .milliseconds(400))
    }
}

extension OverhearTestCase {
    @MainActor
    func makeHarness(transcribing text: String,
                     configure: (AppSettings) -> Void = { _ in }) async throws -> ControllerHarness {
        try await makeHarness(transcriber: StubTranscriber(text: text), configure: configure)
    }

    @MainActor
    func makeHarness(transcriber: any Transcribing,
                     configure: (AppSettings) -> Void = { _ in }) async throws -> ControllerHarness {
        let appState = AppState()
        let injector = SpyInjector()
        let audio = ScriptedAudioSource()
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        configure(settings)

        let controller = EngineController(
            appState: appState,
            injector: injector,
            modelsDirectory: EngineTestModels.directory,
            makeTranscriber: { _ in transcriber },
            makeAudioSource: { audio },
            settings: settings
        )

        controller.start()
        audio.sendSilence(seconds: 0.2)
        await waitUntil("engine reaches idle") { appState.status == .idle }
        controller.activate()
        await waitUntil("engine is ready") { appState.status == .ready }

        return ControllerHarness(controller: controller,
                                 appState: appState,
                                 injector: injector,
                                 audio: audio,
                                 settings: settings)
    }
}
