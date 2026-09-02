import XCTest
@testable import Overhear

/// `Specs/StatusDisplay.md` — the mark the menu bar icon and the overlay both
/// draw. They share one state so the two can never tell the user different
/// things about the same moment.
final class MarkStateTests: XCTestCase {

    /// The three states the user is meant to be able to tell apart at a glance:
    /// listening, hearing speech, and working on it.
    func testEachActiveStatusHasItsOwnMark() {
        XCTAssertEqual(MarkState(status: .ready, showCancelled: false), .listening)
        XCTAssertEqual(MarkState(status: .listening, showCancelled: false), .hearing)
        XCTAssertEqual(MarkState(status: .transcribing, showCancelled: false), .transcribing)
    }

    /// Everything that is not dictation reads as idle. A user who has stopped,
    /// or whose engine is still loading, is not told three different stories
    /// about a microphone that is not listening.
    func testEveryOtherStatusIsIdle() {
        for status in [EngineStatus.stopped, .installing, .loading, .idle, .error] {
            XCTAssertEqual(MarkState(status: status, showCancelled: false), .idle,
                           "\(status) should read as idle")
        }
    }

    /// Cancelling wins over whatever the engine is doing underneath. It is a
    /// second of feedback laid over the current state, and the state it covers
    /// is usually `ready` — which would otherwise draw the same mark as if
    /// nothing had happened.
    func testCancellingShowsOverAnyStatus() {
        for status in [EngineStatus.ready, .listening, .transcribing, .idle, .stopped] {
            XCTAssertEqual(MarkState(status: status, showCancelled: true), .cancelled,
                           "the cancelled mark should survive \(status)")
        }
    }
}
