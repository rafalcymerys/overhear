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

    /// Coming up is its own mark rather than the resting one. A user watching a
    /// model load should see that something is happening, not a dot that looks
    /// the same as one waiting to be asked.
    func testComingUpIsNotTheRestingMark() {
        XCTAssertEqual(MarkState(status: .loading, showCancelled: false), .loading)
        XCTAssertEqual(MarkState(status: .installing, showCancelled: false), .loading)
    }

    /// What is left reads as idle: stopped, and loaded but not dictating.
    func testTheRestIsIdle() {
        for status in [EngineStatus.stopped, .idle] {
            XCTAssertEqual(MarkState(status: status, showCancelled: false), .idle,
                           "\(status) should read as idle")
        }
    }

    /// Setup outstanding is the one thing that has to reach the bar whatever
    /// the engine is doing, since the engine cannot be doing anything useful.
    func testSetupOutstandingAsksForAttention() {
        for status in [EngineStatus.stopped, .idle, .loading, .installing] {
            XCTAssertEqual(MarkState(status: status, showCancelled: false, needsSetup: true),
                           .needsAttention,
                           "\(status) with setup outstanding should ask for attention")
        }
    }

    /// An engine that failed draws the same mark. Both mean dictation cannot
    /// happen and only the user can change it; the menu is where they differ.
    func testAFailedEngineAsksForAttentionToo() {
        XCTAssertEqual(MarkState(status: .error, showCancelled: false), .needsAttention)
    }

    /// Setup being finished is not by itself a reason to look healthy — a
    /// failure underneath it still shows.
    func testFinishedSetupDoesNotHideAFailure() {
        XCTAssertEqual(MarkState(status: .error, showCancelled: false, needsSetup: false),
                       .needsAttention)
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
