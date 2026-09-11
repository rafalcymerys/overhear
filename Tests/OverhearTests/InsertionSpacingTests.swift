import XCTest
@testable import Overhear

/// `Specs/Spacing.md` — the rule on its own, with the caret placed by hand
/// rather than read out of an application.
final class InsertionSpacingTests: XCTestCase {
    private func insert(_ text: String, between left: Character?, and right: Character?) -> String {
        InsertionSpacing.apply(to: text, in: CaretContext(before: left, after: right))
    }

    // MARK: - Before the insertion

    func testAddsASpaceAfterExistingText() {
        XCTAssertEqual(insert("Hello.", between: "o", and: nil), " Hello.")
    }

    func testAddsNothingWhenWhitespaceIsAlreadyThere() {
        for existing: Character in [" ", "\t", "\n"] {
            XCTAssertEqual(insert("Hello.", between: existing, and: nil), "Hello.",
                           "\(existing.debugDescription) already separates the two")
        }
    }

    func testAddsNothingAtTheStartOfAField() {
        XCTAssertEqual(insert("Hello.", between: nil, and: nil), "Hello.")
    }

    func testAddsNothingAfterSomethingThatOpens() {
        for opener: Character in ["(", "[", "{", "\"", "'", "\u{201C}", "\u{2018}", "¿", "¡"] {
            XCTAssertEqual(insert("Hello.", between: opener, and: nil), "Hello.",
                           "\(opener) takes what follows it without a gap")
        }
    }

    /// A hyphen ends a word as often as it joins one, and an em dash is
    /// punctuation between words rather than something that opens one.
    func testHyphensAndDashesTakeASpace() {
        XCTAssertEqual(insert("Hello.", between: "-", and: nil), " Hello.")
        XCTAssertEqual(insert("Hello.", between: "\u{2014}", and: nil), " Hello.")
    }

    func testAddsNothingBeforeTextThatBringsItsOwnSpace() {
        XCTAssertEqual(insert(" Hello.", between: "o", and: nil), " Hello.")
    }

    func testAddsNothingBeforeTextThatStartsWithAttachingPunctuation() {
        XCTAssertEqual(insert(", and then some.", between: "o", and: nil), ", and then some.")
    }

    // MARK: - After the insertion

    func testSpacesBothSidesOfAMidSentenceInsertion() {
        XCTAssertEqual(insert("Hello.", between: "r", and: "t"), " Hello. ")
    }

    func testAddsNothingBeforePunctuationThatAttaches() {
        for following: Character in [".", ",", ";", ":", "!", "?", ")", "]", "}", "\"", "'", "\u{201D}", "\u{2019}"] {
            XCTAssertEqual(insert("Hello", between: "r", and: following), " Hello",
                           "\(following) belongs to the word in front of it")
        }
    }

    /// Only the left of the pair is asked whether it opens something, so an
    /// insertion that lands in front of a bracket is still separated from it.
    func testAddsASpaceBeforeSomethingThatOpens() {
        XCTAssertEqual(insert("Hello", between: nil, and: "("), "Hello ")
    }

    func testAddsNothingBeforeWhitespaceOrTheEndOfTheField() {
        XCTAssertEqual(insert("Hello", between: nil, and: " "), "Hello")
        XCTAssertEqual(insert("Hello", between: nil, and: "\n"), "Hello")
        XCTAssertEqual(insert("Hello", between: nil, and: nil), "Hello")
    }

    func testAddsNothingAfterTextThatBringsItsOwnSpace() {
        XCTAssertEqual(insert("Hello ", between: nil, and: "w"), "Hello ")
    }

    func testSidesAreDecidedIndependently() {
        XCTAssertEqual(insert("Hello", between: "o", and: "."), " Hello")
        XCTAssertEqual(insert("Hello", between: " ", and: "w"), "Hello ")
    }

    // MARK: - Scripts that separate words without spaces

    func testAddsNothingBetweenCharactersOfASpacelessScript() {
        XCTAssertEqual(insert("这是一个测试。", between: "好", and: nil), "这是一个测试。")
        XCTAssertEqual(insert("テスト", between: "私", and: "は"), "テスト")
        XCTAssertEqual(insert("ทดสอบ", between: "ก", and: "ข"), "ทดสอบ")
        XCTAssertEqual(insert("这是一个测试", between: "\u{FF0C}", and: nil), "这是一个测试",
                       "a fullwidth comma is part of the same writing system")
    }

    /// It is the pair meeting at the caret that decides, not the language of
    /// the utterance: a script boundary is still a word boundary.
    func testSpacesWhereTheTwoScriptsMeet() {
        XCTAssertEqual(insert("Hello.", between: "好", and: nil), " Hello.")
        XCTAssertEqual(insert("你好", between: "o", and: nil), " 你好")
    }

    // MARK: - Nothing to insert

    func testTextWithNothingInItIsUntouched() {
        XCTAssertEqual(insert("", between: "o", and: "t"), "",
                       "a transcription that filtered away must not become a space")
    }

    func testWhitespaceOnlyTextIsUntouched() {
        XCTAssertEqual(insert(" ", between: "o", and: "t"), " ")
    }
}
