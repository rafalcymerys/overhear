import XCTest
@testable import Overhear

/// `Specs/Casing.md` — the rule on its own, with the sentence before the caret
/// written out by hand rather than read out of an application.
final class InsertionCasingTests: XCTestCase {
    private func insert(_ text: String, after before: String) -> String {
        InsertionCasing.apply(to: text, in: CaretContext(before: before, after: nil))
    }

    // MARK: - Which way it cases

    func testContinuesAHalfWrittenSentence() {
        XCTAssertEqual(insert("Hello.", after: "The fox jumps over "), "hello.")
    }

    func testLeavesANewSentenceCapitalised() {
        for ender in [".", "!", "?", "\u{2026}"] {
            XCTAssertEqual(insert("Hello.", after: "The fox jumps\(ender) "), "Hello.",
                           "\(ender) ends a sentence")
        }
    }

    func testCapitalisesATranscriptionThatArrivesLowercase() {
        XCTAssertEqual(insert("hello there.", after: "The fox jumps. "), "Hello there.")
    }

    func testCapitalisesAtTheStartOfAField() {
        XCTAssertEqual(insert("hello.", after: ""), "Hello.")
    }

    /// The same fallback, reached the other way: a field that would not say
    /// what surrounds the caret has no sentence to continue.
    func testCapitalisesWhenTheFieldSaysNothing() {
        XCTAssertEqual(InsertionCasing.apply(to: "hello.", in: .unknown), "Hello.")
    }

    func testANewLineStartsASentence() {
        XCTAssertEqual(insert("hello.", after: "The fox jumps over\n"), "Hello.")
        XCTAssertEqual(insert("hello.", after: "The fox jumps over\n\n"), "Hello.")
        XCTAssertEqual(insert("hello.", after: "The fox jumps over\n   "), "Hello.")
    }

    func testReadsBackOverWhitespace() {
        XCTAssertEqual(insert("Hello.", after: "The fox jumps.   "), "Hello.")
        XCTAssertEqual(insert("Hello.", after: "The fox jumps over\t"), "hello.")
    }

    func testReadsBackOverClosingPunctuation() {
        XCTAssertEqual(insert("hello.", after: "He said \u{201C}The fox jumps.\u{201D} "), "Hello.")
        XCTAssertEqual(insert("hello.", after: "The fox jumps.) "), "Hello.")
        XCTAssertEqual(insert("Hello.", after: "The fox (jumps) "), "hello.",
                       "a closing bracket with a letter behind it is still mid-sentence")
    }

    func testOpensAQuotationWithACapital() {
        XCTAssertEqual(insert("hello.", after: "He said \""), "Hello.")
        XCTAssertEqual(insert("hello.", after: "He said \u{201C}"), "Hello.")
    }

    /// A straight or curly single quote is an apostrophe more often than it is
    /// a quotation mark, and nothing in the field says which.
    func testSingleQuotesDoNotOpenASentence() {
        XCTAssertEqual(insert("Hello.", after: "The dogs' "), "hello.")
        XCTAssertEqual(insert("Hello.", after: "The dogs\u{2019} "), "hello.")
    }

    func testOpeningBracketsSayNothingEitherWay() {
        for bracket in ["(", "[", "{"] {
            XCTAssertEqual(insert("Hello.", after: "The fox jumps \(bracket)"), "hello.",
                           "\(bracket) inside a sentence is a parenthetical")
            XCTAssertEqual(insert("hello.", after: "The fox jumps. \(bracket)"), "Hello.",
                           "\(bracket) after a full stop still follows the full stop")
        }
        XCTAssertEqual(insert("hello.", after: "("), "Hello.",
                       "a bracket with nothing behind it is the start of the field")
    }

    func testSpanishOpeningMarksStartASentence() {
        XCTAssertEqual(insert("estoy muy bien.", after: "¿"), "Estoy muy bien.")
        XCTAssertEqual(insert("estoy muy bien.", after: "¡"), "Estoy muy bien.")
        XCTAssertEqual(insert("Estoy muy bien.", after: "Dijo que "), "estoy muy bien.")
    }

    func testMidSentencePunctuationDoesNotStartASentence() {
        for mark in [",", ";", ":", "-", "\u{2014}"] {
            XCTAssertEqual(insert("Hello.", after: "The fox jumps\(mark) "), "hello.",
                           "\(mark) does not end a sentence")
        }
        XCTAssertEqual(insert("Hello.", after: "I counted 3 "), "hello.")
    }

    func testInsertsInsideAWord() {
        XCTAssertEqual(insert("Hello.", after: "Hell"), "hello.")
    }

    // MARK: - Words that keep their case

    func testAcronymsKeepTheirCapitals() {
        XCTAssertEqual(insert("NASA hired her.", after: "I heard that "), "NASA hired her.")
        XCTAssertEqual(insert("AI did it.", after: "I heard that "), "AI did it.",
                       "two letters is enough to be an acronym")
    }

    func testASingleCapitalIsNotAnAcronym() {
        XCTAssertEqual(insert("A dog ran.", after: "I saw "), "a dog ran.")
    }

    func testAWordWithACapitalInsideItKeepsItsCase() {
        XCTAssertEqual(insert("iPhone screens crack.", after: "I think "), "iPhone screens crack.")
        XCTAssertEqual(insert("iPhone screens crack.", after: "The fox jumps. "), "iPhone screens crack.",
                       "capitalising it would make IPhone")
        XCTAssertEqual(insert("McDonald arrived.", after: "I think "), "McDonald arrived.")
    }

    func testTheEnglishIKeepsItsCapital() {
        XCTAssertEqual(insert("I was late.", after: "She left because "), "I was late.")
        for contraction in ["I'm", "I'll", "I've", "I'd", "I\u{2019}m"] {
            XCTAssertEqual(insert("\(contraction) late.", after: "She left because "), "\(contraction) late.")
        }
    }

    func testAWordMerelyBeginningWithIIsNotSpared() {
        XCTAssertEqual(insert("It was late.", after: "She left because "), "it was late.")
    }

    // MARK: - Which character it cases

    func testOnlyTheFirstCharacterChanges() {
        XCTAssertEqual(insert("The quick brown Fox jumps.", after: "I said "),
                       "the quick brown Fox jumps.",
                       "a proper noun further in keeps its capital")
        XCTAssertEqual(insert("hello there. another sentence.", after: "The fox jumps. "),
                       "Hello there. another sentence.",
                       "the second sentence is not the front of what was given")
    }

    func testLeadingPunctuationIsSteppedOver() {
        XCTAssertEqual(insert("\"Hello,\" he said.", after: "He said "), "\"hello,\" he said.")
        XCTAssertEqual(insert("(Hello.)", after: "He said "), "(hello.)")
        XCTAssertEqual(insert("¿Cómo estás?", after: "Me preguntó "), "¿cómo estás?")
    }

    func testTextArrivingWithItsOwnSpaceIsCasedAtItsFirstLetter() {
        XCTAssertEqual(insert(" Hello.", after: "The fox jumps over "), " hello.",
                       "the space is kept and the letter behind it is the one cased")
    }

    func testTextWithNoCaseIsLeftAlone() {
        XCTAssertEqual(insert("1999 was a good year.", after: "The fox jumps. "),
                       "1999 was a good year.",
                       "hunting past the digit would give 1999 Was a good year")
        XCTAssertEqual(insert("3 dogs ran.", after: "The fox jumps. "), "3 dogs ran.")
        XCTAssertEqual(insert("🎙 is on.", after: "The fox jumps. "), "🎙 is on.")
        XCTAssertEqual(insert(", and then some.", after: "The fox jumps. "), ", and then some.",
                       "attaching punctuation is not stepped over")
    }

    func testScriptsWithNoCaseAreUnchanged() {
        XCTAssertEqual(insert("这是一个测试。", after: "你好"), "这是一个测试。")
        XCTAssertEqual(insert("テスト", after: "私は"), "テスト")
    }

    func testAFullwidthFullStopEndsASentence() {
        XCTAssertEqual(insert("hello.", after: "你好。"), "Hello.")
        XCTAssertEqual(insert("Hello.", after: "你好"), "hello.",
                       "no full stop, so the sentence is still running")
    }

    // MARK: - Nothing to case

    func testTextWithNothingInItIsUntouched() {
        XCTAssertEqual(insert("", after: "The fox jumps over "), "")
        XCTAssertEqual(insert("   ", after: "The fox jumps over "), "   ")
    }
}
