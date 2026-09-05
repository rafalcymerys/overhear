import AppKit
import XCTest
@testable import Overhear

/// `Specs/Setup.md` — where the setup window ends up once a macOS permission
/// dialog has come and gone.
///
/// The front is the one thing a test process cannot be given, so the AppKit
/// call that asks for it is injected and counted. The window is still ordered
/// front for real, because the controller refuses to raise one that is not on
/// screen and that has to stay true.
@MainActor
final class SetupWindowTests: OverhearTestCase {
    /// Stands in for the app coming forward: counts the asking, and puts the
    /// window on screen so `isVisible` means what it does in the app.
    private final class FakeFront {
        private(set) var count = 0

        func make() -> SetupWindowController.System {
            // Held strongly: the controller outlives the test that made it,
            // and a subscription that fires afterwards must not be fatal.
            SetupWindowController.System(bringToFront: { window in
                self.count += 1
                window.makeKeyAndOrderFront(nil)
            })
        }
    }

    private let front = FakeFront()

    /// Setup with the model still outstanding, so granting a permission leaves
    /// something for the window to come back to.
    private func makeWindow(system: FakePermissionSystem)
        -> (controller: SetupWindowController, harness: SetupHarness) {
        let harness = makeSetup(system: system)
        let controller = SetupWindowController(setup: harness.setup, system: front.make())
        // A window left on screen keeps the coordinator alive, and the poll it
        // started outlives the fakes underneath it. Shutting it stops both.
        addTeardownBlock { @MainActor in controller.close() }
        return (controller, harness)
    }

    // MARK: - Opening

    func testOpeningTheWindowAsksForTheFront() {
        let (controller, harness) = makeWindow(system: FakePermissionSystem())

        controller.show()

        XCTAssertFalse(harness.setup.isComplete, "the window is up because setup still wants something")
        XCTAssertEqual(front.count, 1)
        XCTAssertTrue(controller.window?.isVisible == true)
    }

    // MARK: - After a permission dialog

    func testTheWindowComesBackWhenTheMicrophoneIsGranted() async {
        let system = FakePermissionSystem()
        let (controller, harness) = makeWindow(system: system)
        controller.show()

        harness.setup.request(.microphone)

        await waitUntil("the window asks for the front again") { self.front.count == 2 }
    }

    /// A dismissed dialog is an answer too. The window has lost the front
    /// either way, and the card still wants the user.
    func testTheWindowComesBackWhenTheDialogIsDismissed() async {
        let system = FakePermissionSystem()
        system.microphoneAnswer = false
        let (controller, harness) = makeWindow(system: system)
        controller.show()

        harness.setup.request(.microphone)

        XCTAssertEqual(harness.setup.permissions.state(of: .microphone), .denied)
        await waitUntil("the window asks for the front again") { self.front.count == 2 }
    }

    /// Accessibility has no completion to wait on — it is switched on in System
    /// Settings and the polling notices. The window comes forward on the answer
    /// all the same.
    func testTheWindowComesBackWhenAccessibilityIsGranted() async {
        let system = FakePermissionSystem()
        let (controller, harness) = makeWindow(system: system)
        controller.show()

        harness.grant(.textInsertion)

        await waitUntil("the window asks for the front again") { self.front.count == 2 }
    }

    /// Two answers, two returns. The second ask is the one that was reported:
    /// granting in System Settings after a dismissed dialog left the window
    /// behind the browser just as the first ask did.
    func testEveryAnswerBringsItForward() async {
        let system = FakePermissionSystem()
        system.microphoneAnswer = false
        let (controller, harness) = makeWindow(system: system)
        controller.show()

        harness.setup.request(.microphone)
        await waitUntil("the first return") { self.front.count == 2 }

        harness.grant(.textInsertion)
        await waitUntil("the second return") { self.front.count == 3 }
    }

    // MARK: - When it must stay where it is

    /// The window closes on the grant that finishes setup, and pulling it
    /// forward on the way out would take the front from whatever the user went
    /// back to.
    func testTheGrantThatFinishesSetupDoesNotRaiseTheWindow() async {
        let system = FakePermissionSystem()
        system.textInsertion = .granted
        let (controller, harness) = makeWindow(system: system)
        controller.show()
        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperBase)

        harness.grant(.microphone)

        XCTAssertTrue(harness.setup.isComplete)
        await assertNever("the window to be raised as setup finishes") { self.front.count > 1 }
    }

    /// The states are reassigned every second while the window is up. A poll
    /// that reads back what it already knew is not an answer.
    func testPollingDoesNotKeepRaisingTheWindow() async {
        let (controller, harness) = makeWindow(system: FakePermissionSystem())
        controller.show()
        harness.setup.permissions.beginWatching(interval: 0.02)

        await assertNever("the window to be raised by the poll") { self.front.count > 1 }
    }

    /// A permission switched off is switched off in System Settings, where the
    /// user still is. Nothing was asked for, so nothing jumps in front of it.
    func testARevocationDoesNotRaiseTheWindow() async {
        let system = FakePermissionSystem()
        system.microphone = .granted
        let (controller, harness) = makeWindow(system: system)
        controller.show()

        harness.revoke(.microphone)

        await assertNever("the window to be raised by a revocation") { self.front.count > 1 }
    }

    func testAClosedWindowIsNotReopenedByAnAnswer() async {
        let system = FakePermissionSystem()
        let (controller, harness) = makeWindow(system: system)
        controller.show()
        controller.close()

        harness.setup.request(.microphone)

        await assertNever("the closed window to come back") { self.front.count > 1 }
    }

    // MARK: - What counts as an answer

    func testAnswersAreTheOnesThatWereStillOpen() {
        let open: [Permission: PermissionState] = [.microphone: .notDetermined, .textInsertion: .notDetermined]

        XCTAssertTrue(SetupWindowController.wasAnswered(
            from: open, to: [.microphone: .granted, .textInsertion: .notDetermined]))
        XCTAssertTrue(SetupWindowController.wasAnswered(
            from: open, to: [.microphone: .denied, .textInsertion: .notDetermined]))
        XCTAssertTrue(SetupWindowController.wasAnswered(
            from: open, to: [.microphone: .notDetermined, .textInsertion: .granted]))

        XCTAssertFalse(SetupWindowController.wasAnswered(from: open, to: open))
        XCTAssertFalse(SetupWindowController.wasAnswered(
            from: [.microphone: .granted, .textInsertion: .granted],
            to: [.microphone: .denied, .textInsertion: .granted]))
        XCTAssertFalse(SetupWindowController.wasAnswered(
            from: [.microphone: .denied, .textInsertion: .granted],
            to: [.microphone: .denied, .textInsertion: .granted]))
    }
}
