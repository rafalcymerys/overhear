import AppKit
import XCTest
@testable import Overhear

/// B17 — clipboard save/restore.
///
/// Every test here uses a uniquely named private pasteboard rather than
/// `.general`, so running the suite never disturbs the real clipboard, and
/// substitutes `performPaste` so no synthetic Cmd+V reaches the focused app.
@MainActor
final class TextInjectorTests: OverhearTestCase {
    // XCTest's setUp/tearDown are nonisolated; XCTest runs them serially on
    // the same thread as the test body, so this is safe.
    nonisolated(unsafe) private var pasteboard: NSPasteboard!

    override func setUpWithError() throws {
        try super.setUpWithError()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("overhear.tests.\(UUID().uuidString)"))
    }

    override func tearDownWithError() throws {
        pasteboard.releaseGlobally()
        pasteboard = nil
        try super.tearDownWithError()
    }

    private func makeInjector(restoreDelay: TimeInterval = 0.05,
                              onPaste: @escaping () -> Void = {}) -> PasteboardTextInjector {
        var injector = PasteboardTextInjector()
        injector.pasteboard = pasteboard
        injector.performPaste = onPaste
        injector.restoreDelay = restoreDelay
        return injector
    }

    func testTextIsPlacedOnThePasteboardBeforePasting() {
        var contentsAtPasteTime: String?
        let injector = makeInjector(onPaste: { [pasteboard] in
            contentsAtPasteTime = pasteboard?.string(forType: .string)
        })

        injector.inject(text: "hello world")

        XCTAssertEqual(contentsAtPasteTime, "hello world",
                       "the text must be on the pasteboard when Cmd+V is delivered")
    }

    func testPasteIsTriggeredExactlyOnce() {
        var pasteCount = 0
        let injector = makeInjector(onPaste: { pasteCount += 1 })

        injector.inject(text: "hello")

        XCTAssertEqual(pasteCount, 1)
    }

    func testPreviousClipboardIsRestored() async {
        pasteboard.clearContents()
        pasteboard.setString("something the user copied", forType: .string)

        let injector = makeInjector()
        injector.inject(text: "dictated text")

        await waitUntil("clipboard restored") {
            self.pasteboard.string(forType: .string) == "something the user copied"
        }
    }

    func testEmptyClipboardLeavesTheInjectedTextBehind() async {
        pasteboard.clearContents()

        let injector = makeInjector()
        injector.inject(text: "dictated text")

        // With nothing to restore, the injected text stays on the pasteboard.
        // Documented rather than asserted as desirable — see TESTING.md.
        await assertNever("the pasteboard being cleared", within: 0.4) {
            self.pasteboard.string(forType: .string) != "dictated text"
        }
    }

    func testRestoreSurvivesRepeatedInjections() async {
        XCTExpectFailure("""
            Known bug: two injections inside the restore window corrupt the \
            clipboard. The second call reads the *first injected text* as \
            "previous contents", so the two pending restores race and the user's \
            original clipboard is replaced by a transcription. Reachable by \
            clicking two entries in the Last Transcriptions menu in quick \
            succession.
            """)

        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)

        let injector = makeInjector()
        injector.inject(text: "first")
        injector.inject(text: "second")

        await waitUntil("clipboard restored after both injections", timeout: 1.0) {
            self.pasteboard.string(forType: .string) == "original"
        }
    }

    func testUnicodeTextRoundTrips() {
        var seen: String?
        let injector = makeInjector(onPaste: { [pasteboard] in
            seen = pasteboard?.string(forType: .string)
        })

        injector.inject(text: "zażółć gęślą jaźń 🎙")

        XCTAssertEqual(seen, "zażółć gęślą jaźń 🎙")
    }
}
