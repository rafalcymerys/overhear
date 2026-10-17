import XCTest
@testable import Overhear

/// Waiting for the engine to reach idle before dictating — what a launch set
/// to listen, a model swap and a settings reload all lean on to resume.
@MainActor
final class ListeningControllerTests: OverhearTestCase {
    private func makeController(mode: ListeningMode = .alwaysOn) -> (ListeningController, AppState) {
        let appState = AppState()
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        settings.listeningMode = mode
        let engine = EngineController(appState: appState, injector: SpyInjector(), settings: settings)
        let listening = ListeningController(engine: engine, appState: appState, settings: settings)
        return (listening, appState)
    }

    func testWaitsThroughTheLoadAndEndsAtIdle() {
        let (listening, appState) = makeController()
        appState.status = .loading

        listening.listenWhenIdle()
        XCTAssertTrue(listening.isWaitingToListen)

        appState.status = .idle
        XCTAssertFalse(listening.isWaitingToListen, "reaching idle is what it was waiting for")
    }

    /// A reload that fails must not leave a start behind for **Try Again** to
    /// set off: the user asked for a load, not for dictation.
    func testAFailedLoadEndsTheWait() {
        let (listening, appState) = makeController()
        appState.status = .loading

        listening.listenWhenIdle()
        appState.status = .error
        XCTAssertFalse(listening.isWaitingToListen)

        appState.status = .loading
        appState.status = .idle
        XCTAssertFalse(listening.isWaitingToListen)
    }

    func testHoldToTalkNeverWaits() {
        let (listening, appState) = makeController(mode: .holdToTalk)
        appState.status = .loading

        listening.listenWhenIdle()
        XCTAssertFalse(listening.isWaitingToListen)
    }
}
