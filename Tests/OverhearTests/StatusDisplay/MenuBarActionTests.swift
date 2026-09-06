import XCTest
@testable import Overhear

/// `Specs/StatusDisplay.md` — what the menu offers where **Start Listening**
/// would go.
///
/// The icon draws one mark for unfinished setup and for an engine that failed,
/// so everything that tells the two apart is here. An engine failure that
/// reaches the menu as **Start Listening** is the bug this covers: the item
/// leads to a toggle that acts only when the status is idle, so clicking it
/// does nothing and says nothing.
final class MenuBarActionTests: XCTestCase {

    // MARK: - Which of the three it is

    func testOffersDictationWhenNothingIsWrong() {
        let action = MenuBarAction(needsSetup: false, status: .idle, failure: nil)

        XCTAssertEqual(action, .dictate(isActive: false))
        XCTAssertEqual(action.title, "Start Listening")
    }

    func testOffersToStopWhileDictating() {
        for status in [EngineStatus.ready, .listening, .transcribing] {
            let action = MenuBarAction(needsSetup: false, status: status, failure: nil)
            XCTAssertEqual(action.title, "Stop Listening", "for \(status)")
        }
    }

    /// R-125: the state between launching and being able to dictate. Offering
    /// **Start Listening** here reaches a toggle that acts only when the status
    /// is idle, so it does nothing for as long as the weights take.
    func testSaysSoWhileTheModelLoads() {
        let action = MenuBarAction(needsSetup: false, status: .loading, failure: nil)

        XCTAssertEqual(action, .loading)
        XCTAssertEqual(action.title, "Loading the model…")
    }

    func testNeverOffersDictationWhileTheModelLoads() {
        let action = MenuBarAction(needsSetup: false, status: .loading, failure: nil)

        XCTAssertNotEqual(action.title, "Start Listening")
        XCTAssertNotEqual(action.title, "Stop Listening")
    }

    /// Loading is what the engine does on the way up, and the engine only comes
    /// up once setup has everything — so unfinished setup is the truer thing to
    /// say, and the window it opens is the one that can act on it.
    func testSetupComesBeforeLoading() {
        let action = MenuBarAction(needsSetup: true, status: .loading, failure: nil)

        XCTAssertEqual(action, .finishSetup)
    }

    /// A load that failed is not a load still running. `.error` is a terminal
    /// state the engine does not leave on its own.
    func testAFailureIsNotMistakenForLoading() {
        let action = MenuBarAction(needsSetup: false, status: .error, failure: "no")

        XCTAssertNotEqual(action, .loading)
    }

    func testOffersSetupWhileAnythingItCoversIsMissing() {
        let action = MenuBarAction(needsSetup: true, status: .idle, failure: nil)

        XCTAssertEqual(action, .finishSetup)
        XCTAssertEqual(action.title, "Finish Setup…")
    }

    /// The one place the engine's message is read. Nothing else in the app
    /// displays it, so a failure that does not reach here is invisible.
    func testNamesTheFailureWhenTheEngineIsDown() {
        let action = MenuBarAction(needsSetup: false,
                                   status: .error,
                                   failure: "Failed to load the cancel word model: bad file")

        XCTAssertEqual(action, .failed(reason: "Failed to load the cancel word model: bad file"))
        XCTAssertEqual(action.title, "Failed to load the cancel word model: bad file")
    }

    /// The whole of R-103: an engine that failed must never be offered an
    /// action that cannot work.
    func testNeverOffersDictationWhileTheEngineIsDown() {
        let action = MenuBarAction(needsSetup: false, status: .error, failure: "anything")

        XCTAssertNotEqual(action.title, "Start Listening")
        XCTAssertNotEqual(action.title, "Stop Listening")
    }

    /// A missing wake word model fails the engine and is also setup's to fetch.
    /// Sending that to **Try Again** would retry a load against a file that is
    /// not there; the window can actually fix it.
    func testSetupComesBeforeAFailedEngine() {
        let action = MenuBarAction(needsSetup: true,
                                   status: .error,
                                   failure: "Failed to load the cancel word model: no such file")

        XCTAssertEqual(action, .finishSetup)
    }

    // MARK: - The line itself

    func testAFailureWithNothingRecordedStillSaysSomething() {
        let action = MenuBarAction(needsSetup: false, status: .error, failure: nil)

        XCTAssertEqual(action, .failed(reason: MenuBarAction.unexplained))
        XCTAssertFalse(action.title.isEmpty)
    }

    /// CoreML's account of a model it could not read runs to several lines, and
    /// a menu that wide is worse than one that trails off.
    func testALongFailureIsCutToOneLine() {
        let reason = String(repeating: "a", count: 200)
        let action = MenuBarAction(needsSetup: false, status: .error, failure: reason)

        XCTAssertEqual(action.title.count, 61, "sixty characters and the ellipsis")
        XCTAssertTrue(action.title.hasSuffix("…"))
    }

    func testAFailureThatFitsIsLeftAlone() {
        let reason = "Transcription failed: the model is not loaded"
        let action = MenuBarAction(needsSetup: false, status: .error, failure: reason)

        XCTAssertEqual(action.title, reason)
    }
}
