import AppKit
import XCTest
@testable import Overhear

/// `Specs/Settings.md` and `Specs/StatusDisplay.md` — what a recorded
/// combination shows as, and what survives a restart.
final class ListeningHotkeyTests: XCTestCase {

    private let controlOptionD = ListeningHotkey(keyCode: 2,
                                                 character: "d",
                                                 modifiers: [.control, .option])

    // MARK: - What the row and the menu show

    func testShowsModifiersInTheOrderMacOSWritesThem() {
        let hotkey = ListeningHotkey(keyCode: 2,
                                     character: "d",
                                     modifiers: [.command, .shift, .option, .control])

        XCTAssertEqual(hotkey.displayString, "⌃⌥⇧⌘D")
    }

    func testShowsTheCombinationRecorded() {
        XCTAssertEqual(controlOptionD.displayString, "⌃⌥D")
    }

    /// A modifier held on its own is the combination hold-to-listen will want,
    /// and it types nothing — so there is a modifier to show and no key.
    func testShowsAModifierHeldOnItsOwn() {
        let rightOption = ListeningHotkey(keyCode: 61, character: "", modifiers: [.option])

        XCTAssertTrue(rightOption.isModifierOnly)
        XCTAssertEqual(rightOption.displayString, "⌥")
    }

    func testNamesKeysThatWouldDrawAsBlank() {
        let hotkey = ListeningHotkey(keyCode: 49, character: " ", modifiers: [.control])

        XCTAssertEqual(hotkey.displayString, "⌃␣")
    }

    /// `NSMenuItem` has no way to draw a modifier on its own, so the item
    /// shows no shortcut rather than a bare ⌥.
    func testAModifierOnItsOwnHasNoMenuKeyEquivalent() {
        let rightOption = ListeningHotkey(keyCode: 61, character: "", modifiers: [.option])

        XCTAssertEqual(rightOption.menuKeyEquivalent, "")
        XCTAssertEqual(controlOptionD.menuKeyEquivalent, "d")
    }

    // MARK: - Storage

    func testRoundTripsThroughStorage() {
        let restored = ListeningHotkey(stored: controlOptionD.stored)

        XCTAssertEqual(restored, controlOptionD)
    }

    func testAModifierOnItsOwnRoundTripsWithTheKeyThatDistinguishesIt() {
        // The flags cannot tell Right Option from Left; the key code is the
        // only thing that can, so it has to survive the trip.
        let rightOption = ListeningHotkey(keyCode: 61, character: "", modifiers: [.option])

        XCTAssertEqual(ListeningHotkey(stored: rightOption.stored), rightOption)
        XCTAssertNotEqual(ListeningHotkey(stored: rightOption.stored),
                          ListeningHotkey(keyCode: 58, character: "", modifiers: [.option]))
    }

    func testRefusesStoredValuesThatAreNotOurs() {
        XCTAssertNil(ListeningHotkey(stored: [:]))
        XCTAssertNil(ListeningHotkey(stored: ["keyCode": "two", "character": "d", "modifiers": 0]))
        XCTAssertNil(ListeningHotkey(stored: ["keyCode": 2, "character": "d"]))
    }

    /// Caps lock and the function bit ride along on presses that have nothing
    /// to do with them — the same combination has to compare equal either way.
    func testNormalizingDropsFlagsAShortcutIsNotWrittenWith() {
        let noisy: NSEvent.ModifierFlags = [.control, .option, .capsLock, .function, .numericPad]

        XCTAssertEqual(ListeningHotkey.normalized(noisy), [.control, .option])
    }
}
