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

    /// Spacing is off unless a test asks for it, and the caret is always the
    /// one the test hands over rather than whatever field happens to be focused
    /// while the suite runs.
    private func makeInjector(restoreDelay: TimeInterval = 0.05,
                              spacing: Bool = false,
                              caret: CaretContext = .unknown,
                              onPaste: @escaping () -> Void = {}) -> PasteboardTextInjector {
        var injector = PasteboardTextInjector()
        injector.pasteboard = pasteboard
        injector.performPaste = onPaste
        injector.restoreDelay = restoreDelay
        injector.spacesInsertedText = { spacing }
        injector.caretContext = { caret }
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

    // MARK: - Spacing

    /// `Specs/Spacing.md` — the rule is exercised in `InsertionSpacingTests`;
    /// what matters here is that the text reaching the pasteboard is the spaced
    /// one, so the spaces arrive as part of the same paste.
    func testSpacedTextIsWhatGetsPasted() {
        var contentsAtPasteTime: String?
        var pasteCount = 0
        let injector = makeInjector(spacing: true,
                                    caret: CaretContext(before: "o", after: "t"),
                                    onPaste: { [pasteboard] in
            contentsAtPasteTime = pasteboard?.string(forType: .string)
            pasteCount += 1
        })

        injector.inject(text: "hello")

        XCTAssertEqual(contentsAtPasteTime, " hello ")
        XCTAssertEqual(pasteCount, 1, "one insertion, so one undo")
    }

    func testTextIsPastedVerbatimWhenTheSettingIsOff() {
        var contentsAtPasteTime: String?
        let injector = makeInjector(spacing: false,
                                    caret: CaretContext(before: "o", after: "t"),
                                    onPaste: { [pasteboard] in
            contentsAtPasteTime = pasteboard?.string(forType: .string)
        })

        injector.inject(text: "hello")

        XCTAssertEqual(contentsAtPasteTime, "hello")
    }

    func testTextIsPastedVerbatimWhenTheFieldSaysNothing() {
        var contentsAtPasteTime: String?
        let injector = makeInjector(spacing: true, caret: .unknown, onPaste: { [pasteboard] in
            contentsAtPasteTime = pasteboard?.string(forType: .string)
        })

        injector.inject(text: "hello")

        XCTAssertEqual(contentsAtPasteTime, "hello",
                       "a field that will not say where the caret is gets no space guessed at")
    }

    func testTheSettingIsReadOnEveryInjection() {
        var spacing = false
        var pasted: [String] = []
        var injector = makeInjector(onPaste: { [pasteboard] in
            pasted.append(pasteboard?.string(forType: .string) ?? "")
        })
        injector.spacesInsertedText = { spacing }
        injector.caretContext = { CaretContext(before: "o", after: nil) }

        injector.inject(text: "hello")
        spacing = true
        injector.inject(text: "hello")

        XCTAssertEqual(pasted, ["hello", " hello"],
                       "turning it on applies to the next utterance, not the next launch")
    }

    func testTheClipboardIsStillRestoredAfterASpacedInsertion() async {
        pasteboard.clearContents()
        pasteboard.setString("something the user copied", forType: .string)

        let injector = makeInjector(spacing: true, caret: CaretContext(before: "o", after: nil))
        injector.inject(text: "dictated text")

        await waitUntil("clipboard restored") {
            self.pasteboard.string(forType: .string) == "something the user copied"
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
