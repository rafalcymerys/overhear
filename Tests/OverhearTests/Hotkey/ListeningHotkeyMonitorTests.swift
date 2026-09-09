import AppKit
import XCTest
@testable import Overhear

/// `Specs/Dictation.md` — what the tap makes of a press and a release, and what
/// it lets through to the app underneath.
///
/// Driven with synthesised events rather than a keyboard: building the tap needs
/// Accessibility and a real keystroke, but deciding what an event means does
/// not, and that decision is the whole difference between a toggle and a hold.
@MainActor
final class ListeningHotkeyMonitorTests: XCTestCase {
    private var monitor: ListeningHotkeyMonitor!
    private var presses = 0
    private var releases = 0

    private let controlOptionD = ListeningHotkey(keyCode: 2,
                                                 character: "d",
                                                 modifiers: [.control, .option])
    private let rightOption = ListeningHotkey(keyCode: 61, character: "", modifiers: [.option])

    override func setUp() {
        super.setUp()
        monitor = ListeningHotkeyMonitor()
        monitor.onPress = { [weak self] in self?.presses += 1 }
        monitor.onRelease = { [weak self] in self?.releases += 1 }
    }

    override func tearDown() {
        // Takes the tap down with it, on a machine where the runner has the
        // Accessibility grant to have built one.
        monitor.update(nil)
        monitor = nil
        super.tearDown()
    }

    // MARK: - Events

    private func key(_ keyCode: UInt16,
                     down: Bool,
                     modifiers: CGEventFlags = [],
                     repeated: Bool = false) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)!
        event.flags = modifiers
        if repeated { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        return event
    }

    private func modifier(_ keyCode: UInt16, held: CGEventFlags) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)!
        event.type = .flagsChanged
        event.flags = held
        return event
    }

    /// - Returns: whether the event reached the app underneath.
    @discardableResult
    private func send(_ event: CGEvent, as type: CGEventType) -> Bool {
        monitor.handle(type: type, event: event) != nil
    }

    // MARK: - A key with modifiers

    func testAPressAndAReleaseAreReportedSeparately() {
        monitor.update(controlOptionD)

        send(key(2, down: true, modifiers: [.maskControl, .maskAlternate]), as: .keyDown)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(releases, 0, "the press is not also a release")

        send(key(2, down: false, modifiers: [.maskControl, .maskAlternate]), as: .keyUp)
        XCTAssertEqual(presses, 1)
        XCTAssertEqual(releases, 1)
    }

    /// Neither half reaches the application: nothing is typed into the document
    /// and there is no alert beep.
    func testNeitherHalfReachesTheApplicationUnderneath() {
        monitor.update(controlOptionD)

        let pressed = send(key(2, down: true, modifiers: [.maskControl, .maskAlternate]), as: .keyDown)
        let released = send(key(2, down: false, modifiers: [.maskControl, .maskAlternate]), as: .keyUp)

        XCTAssertFalse(pressed, "the app underneath never sees the press")
        XCTAssertFalse(released, "nor the key up whose key down it never saw")
    }

    /// Holding the combination for several seconds is one session, not a
    /// repeating toggle.
    func testHoldingIsOnePress() {
        monitor.update(controlOptionD)

        send(key(2, down: true, modifiers: [.maskControl, .maskAlternate]), as: .keyDown)
        for _ in 1...5 {
            let reached = send(key(2, down: true, modifiers: [.maskControl, .maskAlternate], repeated: true), as: .keyDown)
            XCTAssertFalse(reached, "the repeats are swallowed with the press they come from")
        }

        XCTAssertEqual(presses, 1)
        XCTAssertEqual(releases, 0)
    }

    /// A hand coming off ⌃⌥D rarely lets go of all three at once. A release
    /// read as somebody else's key would leave a hold running with nobody
    /// holding it.
    func testTheReleaseIsMatchedEvenIfTheModifiersWentFirst() {
        monitor.update(controlOptionD)

        send(key(2, down: true, modifiers: [.maskControl, .maskAlternate]), as: .keyDown)
        send(key(2, down: false, modifiers: []), as: .keyUp)

        XCTAssertEqual(releases, 1)
    }

    func testAKeyUpWithNoPressBehindItIsLeftAlone() {
        monitor.update(controlOptionD)

        let reached = send(key(2, down: false, modifiers: []), as: .keyUp)

        XCTAssertTrue(reached, "a key Overhear never swallowed belongs to the app underneath")
        XCTAssertEqual(releases, 0)
    }

    func testAnotherCombinationIsLeftAlone() {
        monitor.update(controlOptionD)

        let reached = send(key(2, down: true, modifiers: [.maskCommand]), as: .keyDown)

        XCTAssertTrue(reached)
        XCTAssertEqual(presses, 0)
    }

    /// Recording a shortcut never triggers what it is bound to: the tap is
    /// ahead of Overhear's own window, so it has to stand aside.
    func testASuspendedMonitorReportsNothing() {
        monitor.update(controlOptionD)
        monitor.isSuspended = true

        let reached = send(key(2, down: true, modifiers: [.maskControl, .maskAlternate]), as: .keyDown)

        XCTAssertTrue(reached)
        XCTAssertEqual(presses, 0)
    }

    // MARK: - A modifier held on its own

    func testAModifierIsReportedDownAndUp() {
        monitor.update(rightOption)

        send(modifier(61, held: [.maskAlternate]), as: .flagsChanged)
        XCTAssertEqual(presses, 1)

        send(modifier(61, held: []), as: .flagsChanged)
        XCTAssertEqual(releases, 1)
    }

    /// A modifier types nothing, and every app tracks which ones are down —
    /// swallowing it would leave them believing this one still is.
    func testAModifierStillReachesTheApplication() {
        monitor.update(rightOption)

        XCTAssertTrue(send(modifier(61, held: [.maskAlternate]), as: .flagsChanged))
        XCTAssertTrue(send(modifier(61, held: []), as: .flagsChanged))
    }

    /// Left Option is a different key, which is the distinction
    /// `NSEvent.ModifierFlags` does not carry.
    func testTheOtherSideOfTheKeyboardIsLeftAlone() {
        monitor.update(rightOption)

        send(modifier(58, held: [.maskAlternate]), as: .flagsChanged)

        XCTAssertEqual(presses, 0)
    }

    // MARK: - A key that never comes back up

    func testChangingTheCombinationForgetsTheKeyHeldOnTheOldOne() {
        monitor.update(controlOptionD)
        send(key(2, down: true, modifiers: [.maskControl, .maskAlternate]), as: .keyDown)

        monitor.update(rightOption)
        send(key(2, down: false, modifiers: [.maskControl, .maskAlternate]), as: .keyUp)

        XCTAssertEqual(releases, 0, "the release belonged to a combination that is no longer bound")
    }
}
