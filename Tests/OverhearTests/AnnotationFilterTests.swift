import XCTest
@testable import Overhear

/// R-97: with nobody speaking, the engine was pasting `[ Pause ]` and
/// `(coughing) (coughing)` into whatever the user was typing in. The strings
/// here are the ones from that report.
final class AnnotationFilterTests: XCTestCase {
    private let strict = AnnotationFilter(stripsParentheses: true)
    private let lenient = AnnotationFilter(stripsParentheses: false)

    func testAnUtteranceOfNothingButAnnotationsComesBackEmpty() {
        XCTAssertEqual(strict.filter("[ Pause ]"), "")
        XCTAssertEqual(strict.filter("(coughing) (coughing)"), "")
        XCTAssertEqual(strict.filter("[BLANK_AUDIO]"), "")
        XCTAssertEqual(strict.filter("[Music]"), "")
        XCTAssertEqual(strict.filter("♪ music ♪"), "")
    }

    /// The mixed case matters as much as the pure one: an annotation in the
    /// middle of a real sentence should cost the annotation, not the sentence.
    func testSpeechSurroundingAnAnnotationSurvives() {
        XCTAssertEqual(strict.filter("Hello [ Pause ] world"), "Hello world")
        XCTAssertEqual(strict.filter("(coughing) hello world"), "hello world")
        XCTAssertEqual(strict.filter("hello world (coughing)"), "hello world")
        XCTAssertEqual(strict.filter("Let me think [ Pause ] about it"), "Let me think about it")
    }

    /// Square brackets and musical notes are never dictated, so the setting
    /// does not govern them.
    func testBracketsAndNotesAreStrippedEvenWhenParenthesesAreKept() {
        XCTAssertEqual(lenient.filter("[ Pause ]"), "")
        XCTAssertEqual(lenient.filter("♪ music ♪"), "")
        XCTAssertEqual(lenient.filter("Hello [BLANK_AUDIO] world"), "Hello world")
    }

    /// With the setting off, a parenthesis is treated as something the user
    /// might have said.
    func testParenthesesAreKeptWhenTheSettingIsOff() {
        XCTAssertEqual(lenient.filter("(coughing)"), "(coughing)")
        XCTAssertEqual(lenient.filter("the result (see figure 3) holds"), "the result (see figure 3) holds")
    }

    func testOrdinaryDictationIsUntouched() {
        let samples = [
            "Hello world",
            "Let's meet at 3pm on Tuesday.",
            "The quick brown fox jumps over the lazy dog",
            "Dzień dobry, to jest test rozpoznawania mowy",
        ]
        for sample in samples {
            XCTAssertEqual(strict.filter(sample), sample)
            XCTAssertEqual(lenient.filter(sample), sample)
        }
    }

    /// An unmatched bracket is not an annotation — there is no span to remove,
    /// and eating the rest of the sentence would be worse than leaving it.
    func testAnUnmatchedBracketIsLeftAlone() {
        XCTAssertEqual(strict.filter("a [ b"), "a [ b")
        XCTAssertEqual(strict.filter("2 ) 3"), "2 ) 3")
    }

    func testWhitespaceIsTidiedRatherThanDoubled() {
        XCTAssertEqual(strict.filter("Hello  [ Pause ]   world"), "Hello world")
        XCTAssertEqual(strict.filter("   spaced out   "), "spaced out")
        XCTAssertEqual(strict.filter(""), "")
        XCTAssertEqual(strict.filter("   "), "")
    }
}
