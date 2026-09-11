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

    /// Both insertion settings are off unless a test asks for one, and the
    /// caret is always the one the test hands over rather than whatever field
    /// happens to be focused while the suite runs. Pinned rather than left to
    /// `AppSettings.shared`, which has both of them on.
    private func makeInjector(restoreDelay: TimeInterval = 0.05,
                              spacing: Bool = false,
                              casing: Bool = false,
                              caret: CaretContext = .unknown,
                              onPaste: @escaping () -> Void = {}) -> PasteboardTextInjector {
        var injector = PasteboardTextInjector()
        injector.pasteboard = pasteboard
        injector.performPaste = onPaste
        injector.restoreDelay = restoreDelay
        injector.spacesInsertedText = { spacing }
        injector.matchesSentenceCase = { casing }
        injector.caretContext = { caret }
        return injector
    }

    /// What was on the pasteboard when Cmd+V was delivered, for the tests that
    /// care about the string rather than the timing.
    private func pasted(_ text: String,
                        spacing: Bool = false,
                        casing: Bool = false,
                        caret: CaretContext = .unknown) -> String? {
        var seen: String?
        let injector = makeInjector(spacing: spacing, casing: casing, caret: caret, onPaste: { [pasteboard] in
            seen = pasteboard?.string(forType: .string)
        })
        injector.inject(text: text)
        return seen
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

    // MARK: - Casing

    /// `Specs/Casing.md` — the rule is exercised in `InsertionCasingTests`;
    /// what matters here is that the text reaching the pasteboard is the cased
    /// one, so it arrives as part of the same paste.
    func testCasedTextIsWhatGetsPasted() {
        var contentsAtPasteTime: String?
        var pasteCount = 0
        let injector = makeInjector(casing: true,
                                    caret: CaretContext(before: "The fox jumps over ", after: nil),
                                    onPaste: { [pasteboard] in
            contentsAtPasteTime = pasteboard?.string(forType: .string)
            pasteCount += 1
        })

        injector.inject(text: "Hello.")

        XCTAssertEqual(contentsAtPasteTime, "hello.")
        XCTAssertEqual(pasteCount, 1, "one insertion, so one undo")
    }

    func testCasingIsAppliedBeforeSpacing() {
        var contentsAtPasteTime: String?
        let injector = makeInjector(spacing: true,
                                    casing: true,
                                    caret: CaretContext(before: "The fox jumps over", after: "t"),
                                    onPaste: { [pasteboard] in
            contentsAtPasteTime = pasteboard?.string(forType: .string)
        })

        injector.inject(text: "Hello")

        XCTAssertEqual(contentsAtPasteTime, " hello ",
                       "the space goes around the cased text, not between the rules")
    }

    /// All four combinations against one caret, which sits after a space in the
    /// middle of a sentence: casing has something to do there and spacing does
    /// not, so each setting's effect shows on its own.
    func testTheTwoSettingsAreIndependent() {
        let caret = CaretContext(before: "The fox jumps over ", after: nil)

        XCTAssertEqual(pasted("Hello.", casing: true, caret: caret), "hello.",
                       "casing alone needs no spacing")
        XCTAssertEqual(pasted("Hello.", spacing: true, caret: caret), "Hello.",
                       "spacing alone leaves the capital, and the caret already has its space")
        XCTAssertEqual(pasted("Hello.", spacing: true, casing: true, caret: caret), "hello.")
        XCTAssertEqual(pasted("Hello.", caret: caret), "Hello.",
                       "both off inserts exactly what was transcribed")
    }

    /// The fallback the spec asks for: a field that will not say what surrounds
    /// the caret has no sentence to continue, so the transcription keeps the
    /// capital it arrived with.
    func testCapitalisesWhenTheFieldSaysNothing() {
        var contentsAtPasteTime: String?
        let injector = makeInjector(casing: true, caret: .unknown, onPaste: { [pasteboard] in
            contentsAtPasteTime = pasteboard?.string(forType: .string)
        })

        injector.inject(text: "hello.")

        XCTAssertEqual(contentsAtPasteTime, "Hello.")
    }

    func testTheCasingSettingIsReadOnEveryInjection() {
        var casing = false
        var pasted: [String] = []
        var injector = makeInjector(onPaste: { [pasteboard] in
            pasted.append(pasteboard?.string(forType: .string) ?? "")
        })
        injector.matchesSentenceCase = { casing }
        injector.caretContext = { CaretContext(before: "The fox jumps over ", after: nil) }

        injector.inject(text: "Hello.")
        casing = true
        injector.inject(text: "Hello.")

        XCTAssertEqual(pasted, ["Hello.", "hello."],
                       "turning it on applies to the next utterance, not the next launch")
    }

    /// Two reads of a live application cost twice as much for the same two
    /// answers, and a caret that moved between them would have the rules
    /// disagree about where the insertion landed.
    func testTheFieldIsReadOnceForBothRules() {
        var reads = 0
        var injector = makeInjector(spacing: true, casing: true)
        injector.caretContext = {
            reads += 1
            return CaretContext(before: "The fox jumps over", after: "t")
        }

        injector.inject(text: "Hello")

        XCTAssertEqual(reads, 1)
    }

    func testTheFieldIsNotReadWhenNeitherRuleWantsIt() {
        var reads = 0
        var injector = makeInjector(spacing: false, casing: false)
        injector.caretContext = {
            reads += 1
            return .unknown
        }

        injector.inject(text: "Hello")

        XCTAssertEqual(reads, 0, "nothing to decide, so the application is left alone")
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
