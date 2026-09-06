import AppKit
import XCTest
@testable import Overhear

/// `Specs/Settings.md` — what the row does with the keys pressed at it.
final class HotkeyRecorderTests: XCTestCase {

    /// Spotlight, as System Settings stores it: enabled, Cmd+Space.
    private let spotlight = SystemShortcuts(symbolicHotkeys: [
        "64": ["enabled": true, "value": ["parameters": [32, 49, 1_048_576]]],
    ])

    private func makeRecorder() -> HotkeyRecorder {
        // No system shortcuts at all, so a test that is not about conflicts
        // does not depend on what the machine running it has bound.
        HotkeyRecorder(system: SystemShortcuts(symbolicHotkeys: [:]))
    }

    func testRecordsAKeyWithModifiers() {
        var recorder = makeRecorder()

        let outcome = recorder.keyDown(keyCode: 2, characters: "d", modifiers: [.control, .option])

        XCTAssertEqual(outcome, .recorded(ListeningHotkey(keyCode: 2,
                                                          character: "d",
                                                          modifiers: [.control, .option])))
    }

    /// A letter on its own would be swallowed everywhere the user types.
    func testRefusesAKeyWithNoModifier() {
        var recorder = makeRecorder()

        guard case let .refused(reason) = recorder.keyDown(keyCode: 2, characters: "d", modifiers: []) else {
            return XCTFail("expected a refusal")
        }
        XCTAssertTrue(reason.contains("⌃"), "the refusal says what is missing: \(reason)")
    }

    /// The tap sits ahead of the app but behind the window server's own
    /// bindings, so a combination macOS has taken would do nothing at all.
    func testRefusesACombinationMacOSHasTaken() {
        var recorder = HotkeyRecorder(system: spotlight)

        guard case let .refused(reason) = recorder.keyDown(keyCode: 49, characters: " ", modifiers: [.command]) else {
            return XCTFail("expected a refusal")
        }
        XCTAssertTrue(reason.contains("macOS"), reason)
    }

    func testTakesACombinationMacOSHasNotTaken() {
        var recorder = HotkeyRecorder(system: spotlight)

        let outcome = recorder.keyDown(keyCode: 2, characters: "d", modifiers: [.control, .option])

        XCTAssertEqual(outcome, .recorded(ListeningHotkey(keyCode: 2,
                                                          character: "d",
                                                          modifiers: [.control, .option])))
    }

    func testEscapeCancels() {
        var recorder = makeRecorder()

        XCTAssertEqual(recorder.keyDown(keyCode: 53, characters: "\u{1B}", modifiers: []), .cancelled)
    }

    // MARK: - A modifier held on its own

    /// Held is not yet recorded: it could as easily be the first half of ⌃⌥D.
    /// Letting go with no key pressed is what settles it.
    func testRecordsAModifierWhenItIsLetGoOf() {
        var recorder = makeRecorder()

        XCTAssertEqual(recorder.flagsChanged(keyCode: 61, modifiers: [.option]), .pending)

        XCTAssertEqual(recorder.flagsChanged(keyCode: 61, modifiers: []),
                       .recorded(ListeningHotkey(keyCode: 61, character: "", modifiers: [.option])))
    }

    func testAModifierPressedTowardsAKeyIsNotRecordedOnItsOwn() {
        var recorder = makeRecorder()

        _ = recorder.flagsChanged(keyCode: 61, modifiers: [.option])
        let outcome = recorder.keyDown(keyCode: 2, characters: "d", modifiers: [.option])

        XCTAssertEqual(outcome, .recorded(ListeningHotkey(keyCode: 2,
                                                          character: "d",
                                                          modifiers: [.option])))

        // And the modifier going up afterwards records nothing of its own.
        XCTAssertEqual(recorder.flagsChanged(keyCode: 61, modifiers: []), .pending)
    }

    func testTwoModifiersHeldTogetherAreNotAHotkeyOnTheirOwn() {
        var recorder = makeRecorder()

        _ = recorder.flagsChanged(keyCode: 59, modifiers: [.control])
        _ = recorder.flagsChanged(keyCode: 61, modifiers: [.control, .option])

        XCTAssertEqual(recorder.flagsChanged(keyCode: 61, modifiers: []), .pending)
    }
}
