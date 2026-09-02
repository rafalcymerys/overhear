import XCTest
@testable import Overhear

@MainActor
final class AppStateTests: XCTestCase {

    // B3 — recent transcriptions ring buffer

    func testTranscriptionsAreNewestFirst() {
        let state = AppState()
        state.addTranscription("first")
        state.addTranscription("second")

        XCTAssertEqual(state.recentTranscriptions, ["second", "first"])
    }

    func testOnlyFiveTranscriptionsAreKept() {
        let state = AppState()
        for index in 1...7 {
            state.addTranscription("entry \(index)")
        }

        XCTAssertEqual(state.recentTranscriptions,
                       ["entry 7", "entry 6", "entry 5", "entry 4", "entry 3"])
    }

    // B5 — cancelled indicator lifecycle

    func testCancelledIndicatorClearsItself() async {
        let state = AppState()
        state.triggerCancelled()
        XCTAssertTrue(state.showCancelled)

        await waitUntil("cancelled indicator to clear", timeout: 3.0) { !state.showCancelled }
    }

    func testSecondCancelResetsTheTimer() async {
        let state = AppState()
        state.triggerCancelled()

        // Halfway through the first second, cancel again. If the original timer
        // were still running the indicator would clear early.
        try? await Task.sleep(nanoseconds: 600_000_000)
        state.triggerCancelled()

        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertTrue(state.showCancelled, "timer should have been restarted, not left to fire")

        await waitUntil("cancelled indicator to clear eventually", timeout: 3.0) { !state.showCancelled }
    }

    // Status helpers the menu bar and overlay branch on

    func testActiveStates() {
        XCTAssertTrue(EngineStatus.ready.isActive)
        XCTAssertTrue(EngineStatus.listening.isActive)
        XCTAssertTrue(EngineStatus.transcribing.isActive)

        XCTAssertFalse(EngineStatus.stopped.isActive)
        XCTAssertFalse(EngineStatus.loading.isActive)
        XCTAssertFalse(EngineStatus.idle.isActive)
        XCTAssertFalse(EngineStatus.error.isActive)
    }
}
