import AppKit
import XCTest
@testable import Overhear

/// `Specs/Settings.md` — the row's own behaviour, as opposed to the rules it
/// applies to a press.
@MainActor
final class HotkeyRecordingTests: OverhearTestCase {

    private var settings: AppSettings!
    /// Never given a hotkey, so it never builds a tap — these are about what
    /// the row asks of it, not about what the tap does.
    private var monitor: ListeningHotkeyMonitor!

    private func makeRecording() -> HotkeyRecording {
        settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        monitor = ListeningHotkeyMonitor()
        return HotkeyRecording(settings: settings, monitor: monitor)
    }

    /// Recording never triggers what it is bound to. The tap is ahead of every
    /// app including this one, so it has to be held off while the row is
    /// waiting — otherwise the combination already stored starts dictation
    /// instead of being replaced.
    func testHoldsTheTapOffWhileRecording() {
        let recording = makeRecording()

        recording.begin()
        XCTAssertTrue(recording.isRecording)
        XCTAssertTrue(monitor.isSuspended)

        recording.cancel()
        XCTAssertFalse(recording.isRecording)
        XCTAssertFalse(monitor.isSuspended)
    }

    func testClearingRemovesTheHotkey() {
        let recording = makeRecording()
        settings.listeningHotkey = ListeningHotkey(keyCode: 2, character: "d", modifiers: [.control])

        recording.clear()

        XCTAssertNil(settings.listeningHotkey)
    }
}
