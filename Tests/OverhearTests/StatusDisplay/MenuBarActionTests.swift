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

    // MARK: - The shortcut the item shows

    private let controlOptionD = ListeningHotkey(keyCode: 2,
                                                 character: "d",
                                                 modifiers: [.control, .option])

    func testTheListeningItemShowsTheHotkey() {
        for status in [EngineStatus.idle, .ready, .listening, .transcribing] {
            let action = MenuBarAction(needsSetup: false, status: status, failure: nil, mode: .alwaysOn, hotkey: nil)
            let shortcut = action.shortcut(controlOptionD)

            XCTAssertEqual(shortcut.keyEquivalent, "d", "for \(status)")
            XCTAssertEqual(shortcut.modifiers, [.control, .option], "for \(status)")
        }
    }

    /// Not ⌘D, which is what the item advertised before there was a hotkey to
    /// show — a menu's own key equivalent fires only while that menu is open.
    func testTheListeningItemShowsNothingWithNoHotkeyRecorded() {
        let action = MenuBarAction(needsSetup: false, status: .idle, failure: nil, mode: .alwaysOn, hotkey: nil)

        XCTAssertEqual(action.shortcut(nil).keyEquivalent, "")
        XCTAssertEqual(action.shortcut(nil).modifiers, [])
    }

    /// The lines that replace the item cannot be clicked, and the hotkey is
    /// inert in the states they stand for.
    func testTheStatesThatReplaceDictationShowNoShortcut() {
        let actions = [
            MenuBarAction(needsSetup: true, status: .idle, failure: nil, mode: .alwaysOn, hotkey: nil),
            MenuBarAction(needsSetup: false, status: .loading, failure: nil, mode: .alwaysOn, hotkey: nil),
            MenuBarAction(needsSetup: false, status: .error, failure: "no model", mode: .alwaysOn, hotkey: nil),
        ]

        for action in actions {
            XCTAssertEqual(action.shortcut(controlOptionD).keyEquivalent, "", "for \(action)")
            XCTAssertEqual(action.shortcut(controlOptionD).modifiers, [], "for \(action)")
        }
    }

    func testAModifierHeldOnItsOwnIsNotDrawnAsAShortcut() {
        let rightOption = ListeningHotkey(keyCode: 61, character: "", modifiers: [.option])
        let action = MenuBarAction(needsSetup: false, status: .idle, failure: nil, mode: .alwaysOn, hotkey: nil)

        XCTAssertEqual(action.shortcut(rightOption).keyEquivalent, "")
        XCTAssertEqual(action.shortcut(rightOption).modifiers, [])
    }

    // MARK: - Which of the three it is

    func testOffersDictationWhenNothingIsWrong() {
        let action = MenuBarAction(needsSetup: false, status: .idle, failure: nil, mode: .alwaysOn, hotkey: nil)

        XCTAssertEqual(action, .dictate(isActive: false))
        XCTAssertEqual(action.title, "Start Listening")
    }

    func testOffersToStopWhileDictating() {
        for status in [EngineStatus.ready, .listening, .transcribing] {
            let action = MenuBarAction(needsSetup: false, status: status, failure: nil, mode: .alwaysOn, hotkey: nil)
            XCTAssertEqual(action.title, "Stop Listening", "for \(status)")
        }
    }

    /// R-125: the state between launching and being able to dictate. Offering
    /// **Start Listening** here reaches a toggle that acts only when the status
    /// is idle, so it does nothing for as long as the weights take.
    func testSaysSoWhileTheModelLoads() {
        let action = MenuBarAction(needsSetup: false, status: .loading, failure: nil, mode: .alwaysOn, hotkey: nil)

        XCTAssertEqual(action, .loading)
        XCTAssertEqual(action.title, "Loading the model…")
    }

    func testNeverOffersDictationWhileTheModelLoads() {
        let action = MenuBarAction(needsSetup: false, status: .loading, failure: nil, mode: .alwaysOn, hotkey: nil)

        XCTAssertNotEqual(action.title, "Start Listening")
        XCTAssertNotEqual(action.title, "Stop Listening")
    }

    /// Loading is what the engine does on the way up, and the engine only comes
    /// up once setup has everything — so unfinished setup is the truer thing to
    /// say, and the window it opens is the one that can act on it.
    func testSetupComesBeforeLoading() {
        let action = MenuBarAction(needsSetup: true, status: .loading, failure: nil, mode: .alwaysOn, hotkey: nil)

        XCTAssertEqual(action, .finishSetup)
    }

    /// A load that failed is not a load still running. `.error` is a terminal
    /// state the engine does not leave on its own.
    func testAFailureIsNotMistakenForLoading() {
        let action = MenuBarAction(needsSetup: false, status: .error, failure: "no", mode: .alwaysOn, hotkey: nil)

        XCTAssertNotEqual(action, .loading)
    }

    func testOffersSetupWhileAnythingItCoversIsMissing() {
        let action = MenuBarAction(needsSetup: true, status: .idle, failure: nil, mode: .alwaysOn, hotkey: nil)

        XCTAssertEqual(action, .finishSetup)
        XCTAssertEqual(action.title, "Finish Setup…")
    }

    /// The one place the engine's message is read. Nothing else in the app
    /// displays it, so a failure that does not reach here is invisible.
    func testNamesTheFailureWhenTheEngineIsDown() {
        let action = MenuBarAction(needsSetup: false,
                                   status: .error,
                                   failure: "Failed to load the cancel word model: bad file",
                                   mode: .alwaysOn,
                                   hotkey: nil)

        XCTAssertEqual(action, .failed(reason: "Failed to load the cancel word model: bad file"))
        XCTAssertEqual(action.title, "Failed to load the cancel word model: bad file")
    }

    /// The whole of R-103: an engine that failed must never be offered an
    /// action that cannot work.
    func testNeverOffersDictationWhileTheEngineIsDown() {
        let action = MenuBarAction(needsSetup: false, status: .error, failure: "anything", mode: .alwaysOn, hotkey: nil)

        XCTAssertNotEqual(action.title, "Start Listening")
        XCTAssertNotEqual(action.title, "Stop Listening")
    }

    /// A missing wake word model fails the engine and is also setup's to fetch.
    /// Sending that to **Try Again** would retry a load against a file that is
    /// not there; the window can actually fix it.
    func testSetupComesBeforeAFailedEngine() {
        let action = MenuBarAction(needsSetup: true,
                                   status: .error,
                                   failure: "Failed to load the cancel word model: no such file",
                                   mode: .alwaysOn,
                                   hotkey: nil)

        XCTAssertEqual(action, .finishSetup)
    }

    // MARK: - Hold to talk

    /// The key is the only way in and out, so neither **Start Listening** nor
    /// **Stop Listening** appears: an item that started dictation from the
    /// mouse would leave nothing to release.
    func testHoldToTalkNamesTheCombinationInsteadOfOfferingAToggle() {
        for status in [EngineStatus.idle, .ready, .listening, .transcribing] {
            let action = MenuBarAction(needsSetup: false,
                                       status: status,
                                       failure: nil,
                                       mode: .holdToTalk,
                                       hotkey: controlOptionD)

            XCTAssertEqual(action, .holdToTalk(combination: "⌃⌥D"), "for \(status)")
            XCTAssertEqual(action.title, "Hold ⌃⌥D to talk", "for \(status)")
        }
    }

    func testHoldToTalkFollowsAChangeOfCombination() {
        let rightOption = ListeningHotkey(keyCode: 61, character: "", modifiers: [.option])
        let action = MenuBarAction(needsSetup: false,
                                   status: .idle,
                                   failure: nil,
                                   mode: .holdToTalk,
                                   hotkey: rightOption)

        XCTAssertEqual(action.title, "Hold ⌥ to talk")
    }

    /// A line that names a state carries no shortcut of its own — and here the
    /// combination is already in the title.
    func testTheHoldToTalkLineShowsNoShortcut() {
        let action = MenuBarAction(needsSetup: false,
                                   status: .idle,
                                   failure: nil,
                                   mode: .holdToTalk,
                                   hotkey: controlOptionD)

        XCTAssertEqual(action.shortcut(controlOptionD).keyEquivalent, "")
        XCTAssertEqual(action.shortcut(controlOptionD).modifiers, [])
    }

    /// The mode is offered whether or not a combination is recorded, so this
    /// state is reachable — and the menu is where the user finds out that
    /// nothing can start dictation.
    func testHoldToTalkWithNoCombinationLeadsToSettings() {
        let action = MenuBarAction(needsSetup: false,
                                   status: .idle,
                                   failure: nil,
                                   mode: .holdToTalk,
                                   hotkey: nil)

        XCTAssertEqual(action, .setHotkey)
        XCTAssertEqual(action.title, "Set a Listening Hotkey…")
    }

    func testHoldToTalkNeverOffersDictation() {
        for hotkey in [controlOptionD, nil] {
            for status in [EngineStatus.idle, .ready, .listening, .transcribing] {
                let action = MenuBarAction(needsSetup: false,
                                           status: status,
                                           failure: nil,
                                           mode: .holdToTalk,
                                           hotkey: hotkey)

                XCTAssertNotEqual(action.title, "Start Listening", "for \(status)")
                XCTAssertNotEqual(action.title, "Stop Listening", "for \(status)")
            }
        }
    }

    /// Loading, unfinished setup and a failed engine are about the engine, not
    /// the mode, so they still take the line in hold to talk.
    func testTheEngineStatesComeBeforeTheMode() {
        XCTAssertEqual(MenuBarAction(needsSetup: false,
                                     status: .loading,
                                     failure: nil,
                                     mode: .holdToTalk,
                                     hotkey: controlOptionD),
                       .loading)
        XCTAssertEqual(MenuBarAction(needsSetup: true,
                                     status: .idle,
                                     failure: nil,
                                     mode: .holdToTalk,
                                     hotkey: controlOptionD),
                       .finishSetup)
        XCTAssertEqual(MenuBarAction(needsSetup: false,
                                     status: .error,
                                     failure: "no model",
                                     mode: .holdToTalk,
                                     hotkey: controlOptionD),
                       .failed(reason: "no model"))
    }

    /// Choosing always-on listening brings **Start Listening** back, with its
    /// combination against its right edge.
    func testAlwaysOnBringsTheToggleBack() {
        let action = MenuBarAction(needsSetup: false,
                                   status: .idle,
                                   failure: nil,
                                   mode: .alwaysOn,
                                   hotkey: controlOptionD)

        XCTAssertEqual(action, .dictate(isActive: false))
        XCTAssertEqual(action.shortcut(controlOptionD).keyEquivalent, "d")
    }

    // MARK: - The line itself

    func testAFailureWithNothingRecordedStillSaysSomething() {
        let action = MenuBarAction(needsSetup: false, status: .error, failure: nil, mode: .alwaysOn, hotkey: nil)

        XCTAssertEqual(action, .failed(reason: MenuBarAction.unexplained))
        XCTAssertFalse(action.title.isEmpty)
    }

    /// CoreML's account of a model it could not read runs to several lines, and
    /// a menu that wide is worse than one that trails off.
    func testALongFailureIsCutToOneLine() {
        let reason = String(repeating: "a", count: 200)
        let action = MenuBarAction(needsSetup: false, status: .error, failure: reason, mode: .alwaysOn, hotkey: nil)

        XCTAssertEqual(action.title.count, 61, "sixty characters and the ellipsis")
        XCTAssertTrue(action.title.hasSuffix("…"))
    }

    func testAFailureThatFitsIsLeftAlone() {
        let reason = "Transcription failed: the model is not loaded"
        let action = MenuBarAction(needsSetup: false, status: .error, failure: reason, mode: .alwaysOn, hotkey: nil)

        XCTAssertEqual(action.title, reason)
    }
}
