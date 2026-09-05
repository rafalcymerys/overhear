import AppKit
import XCTest
@testable import Overhear

/// `Specs/StatusDisplay.md` — the floating overlay: when it is on screen, where
/// it sits, and how it behaves among other windows.
///
/// The controller is driven through `AppState` and its settings rather than
/// through the engine, which is the same seam the app uses: the overlay knows
/// nothing about dictation beyond the status it is handed.
@MainActor
final class OverlayControllerTests: OverhearTestCase {

    // MARK: - When it is on screen

    /// Nothing is built until there is something to show. A window created at
    /// launch would be one more thing to go wrong before the user has done
    /// anything.
    func testNoWindowExistsBeforeDictationStarts() {
        let overlay = makeOverlay()

        XCTAssertNil(overlay.controller.window)
    }

    func testTheOverlayAppearsWithDictationAndGoesWithIt() async {
        let overlay = makeOverlay()

        overlay.appState.status = .ready
        await waitUntil("the overlay appears") { overlay.controller.window?.isVisible == true }

        overlay.appState.status = .listening
        await assertNever("the overlay to disappear while speaking") {
            overlay.controller.window?.isVisible == false
        }

        overlay.appState.status = .stopped
        await waitUntil("the overlay goes when dictation stops") {
            overlay.controller.window?.isVisible == false
        }
    }

    /// Loading and failing are not dictation, and the overlay says nothing
    /// about either — the menu bar icon carries those.
    func testTheOverlayStaysAwayForEveryStateThatIsNotDictation() async {
        let overlay = makeOverlay()

        for status in [EngineStatus.loading, .idle, .error] {
            overlay.appState.status = status
            await assertNever("the overlay to appear for \(status)") {
                overlay.controller.window?.isVisible == true
            }
        }
    }

    // MARK: - The setting

    func testNoOverlayAppearsWhenTheSettingIsOff() async {
        let overlay = makeOverlay { $0.showOverlay = false }

        overlay.appState.status = .ready
        await assertNever("an overlay to appear with the setting off") {
            overlay.controller.window?.isVisible == true
        }
    }

    /// Turning it off mid-dictation takes the overlay away at once, and turning
    /// it back on brings it back — without dictation being interrupted either
    /// way.
    func testTheSettingAppliesWhileDictating() async {
        let overlay = makeOverlay()
        overlay.appState.status = .ready
        await waitUntil("the overlay appears") { overlay.controller.window?.isVisible == true }

        overlay.settings.showOverlay = false
        await waitUntil("the overlay goes at once") { overlay.controller.window?.isVisible == false }
        XCTAssertEqual(overlay.appState.status, .ready, "dictation is untouched by the setting")

        overlay.settings.showOverlay = true
        await waitUntil("the overlay comes back") { overlay.controller.window?.isVisible == true }
    }

    // MARK: - How the window behaves

    /// The properties the spec's assertions rest on: it floats above other
    /// windows, follows the user between spaces, never takes focus from what
    /// they are typing in, and can be dragged by its background.
    func testTheWindowFloatsWithoutTakingFocus() async throws {
        let overlay = makeOverlay()
        overlay.appState.status = .ready
        await waitUntil("the overlay appears") { overlay.controller.window != nil }

        let window = try XCTUnwrap(overlay.controller.window)
        XCTAssertEqual(window.level, .floating, "a normal level would hide it behind other windows")
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces),
                      "it should follow the user into a full-screen app")
        XCTAssertFalse(window.canBecomeKey, "taking focus would interrupt whatever is being typed in")
        XCTAssertTrue(window.isMovableByWindowBackground, "the overlay is dragged by its background")
        XCTAssertFalse(window.isOpaque)
    }

    /// It belongs in the top-right corner of the main screen, inset from both
    /// edges.
    func testItSitsInTheTopRightOfTheMainScreen() async throws {
        let overlay = makeOverlay()
        overlay.appState.status = .ready
        await waitUntil("the overlay appears") { overlay.controller.window != nil }

        let window = try XCTUnwrap(overlay.controller.window)
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame

        XCTAssertEqual(window.frame.maxX, screen.maxX - 16, accuracy: 1)
        XCTAssertEqual(window.frame.maxY, screen.maxY - 16, accuracy: 1)
    }

    /// Dragging it moves it for that session; the next time it is shown it is
    /// back in the corner. The spec calls for exactly this — the position is not
    /// remembered.
    func testItReturnsToTheCornerAfterBeingMoved() async throws {
        let overlay = makeOverlay()
        overlay.appState.status = .ready
        await waitUntil("the overlay appears") { overlay.controller.window != nil }

        let window = try XCTUnwrap(overlay.controller.window)
        let corner = window.frame.origin
        window.setFrameOrigin(NSPoint(x: 100, y: 100))
        XCTAssertNotEqual(window.frame.origin, corner)

        overlay.appState.status = .stopped
        await waitUntil("the overlay goes") { window.isVisible == false }
        overlay.appState.status = .ready
        await waitUntil("the overlay comes back") { window.isVisible == true }

        XCTAssertEqual(window.frame.origin.x, corner.x, accuracy: 1)
        XCTAssertEqual(window.frame.origin.y, corner.y, accuracy: 1)
    }

    // MARK: - Support

    private struct Overlay {
        let controller: OverlayController
        let appState: AppState
        let settings: AppSettings
    }

    /// A controller over its own settings, so a test never writes the user's.
    private func makeOverlay(configure: (AppSettings) -> Void = { _ in }) -> Overlay {
        let appState = AppState()
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        configure(settings)

        let controller = OverlayController(
            appState: appState,
            onStop: {},
            onOpenSettings: {},
            settings: settings
        )
        // Ordered out rather than closed: the controller keeps a strong
        // reference, and an NSWindow releases itself on close by default.
        addTeardownBlock { @MainActor in controller.window?.orderOut(nil) }

        return Overlay(controller: controller, appState: appState, settings: settings)
    }
}
