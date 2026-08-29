import WhisperKit
import XCTest
@testable import Overhear

/// R-98: speaking Polish sometimes produced English text.
///
/// Nothing ever asked Whisper to translate — the task was already
/// `.transcribe`. The English came from the language token. Two versions of the
/// same mistake produced it: falling back to the alphabetically first selected
/// language when detection landed outside the set, and skipping detection
/// entirely when only one language was selected. Both replaced the model's
/// judgement with a fixed rule.
final class DecodePolicyTests: XCTestCase {
    private let selected = ["en", "pl"]

    private func policy(_ codes: [String]? = nil, translating: Bool = false) -> DecodePolicy {
        DecodePolicy(selected: codes ?? selected, translatesUnsupported: translating)
    }

    /// Scores as the detector reports them: higher is likelier.
    private func scores(_ pairs: [String: Float]) -> LanguageScores {
        LanguageScores(scores: pairs)
    }

    // MARK: - A selected language is never translated

    func testASelectedLanguageIsTranscribedAsItself() {
        for language in selected {
            for translating in [true, false] {
                let heard = scores([language: -0.1, "de": -4.0])
                XCTAssertEqual(policy(translating: translating).plan(from: heard),
                               DecodePolicy.Plan(language: language, task: .transcribe),
                               "\(language) should be transcribed as itself whatever the setting says")
            }
        }
    }

    // MARK: - Staying inside the user's languages

    /// The bug, as one assertion. Whisper's `base` model routinely reads Polish
    /// as Czech; the user's Polish must win over their English, because the
    /// model scored it higher — not because of any fixed preference.
    func testAMisdetectedLanguageFallsToTheLikeliestSelectedOne() {
        let heard = scores(["cs": -0.2, "pl": -0.9, "en": -5.0])
        XCTAssertEqual(policy().plan(from: heard),
                       DecodePolicy.Plan(language: "pl", task: .transcribe))
    }

    /// The same input with the selection reversed has to come out the other
    /// way, or the ranking is not really being used.
    func testTheRankingDecidesRatherThanAFixedOrder() {
        let leansPolish = scores(["cs": -0.2, "pl": -0.9, "en": -5.0])
        let leansEnglish = scores(["cs": -0.2, "pl": -5.0, "en": -0.9])

        XCTAssertEqual(policy().plan(from: leansPolish).language, "pl")
        XCTAssertEqual(policy().plan(from: leansEnglish).language, "en")
    }

    /// Output stays inside the selected languages — the point of selecting them.
    func testAnUnsupportedLanguageIsDecodedAsTheClosestSelectedOne() {
        let heard = scores(["de": -0.1, "en": -2.0, "pl": -6.0])
        XCTAssertEqual(policy().plan(from: heard),
                       DecodePolicy.Plan(language: "en", task: .transcribe))
    }

    func testAnUnsupportedLanguageIsTranslatedWhenTheSettingIsOn() {
        let heard = scores(["de": -0.1, "en": -2.0, "pl": -6.0])
        XCTAssertEqual(policy(translating: true).plan(from: heard),
                       DecodePolicy.Plan(language: "de", task: .translate))
    }

    /// The setting governs unselected languages only, so turning it on must not
    /// start translating the ones the user chose.
    func testTurningTranslationOnDoesNotAffectSelectedLanguages() {
        let heard = scores(["pl": -0.1, "de": -3.0])
        XCTAssertEqual(policy(translating: true).plan(from: heard),
                       DecodePolicy.Plan(language: "pl", task: .transcribe))
    }

    // MARK: - One selected language

    /// Selecting one language means output is always that language, which is
    /// what selecting it should mean — but it is reached by ranking, so
    /// turning translation on still lets foreign speech out.
    func testOneSelectedLanguageKeepsEverythingInThatLanguage() {
        let heard = scores(["de": -0.1, "en": -3.0])
        XCTAssertEqual(policy(["en"]).plan(from: heard),
                       DecodePolicy.Plan(language: "en", task: .transcribe))
        XCTAssertEqual(policy(["en"], translating: true).plan(from: heard),
                       DecodePolicy.Plan(language: "de", task: .translate))
    }

    // MARK: - Degenerate input

    /// Detection failing should not silently become English: Whisper prefills
    /// `<|en|>` for a nil language, so the user's own choice is the safer answer.
    func testWithoutScoresTheUsersOwnLanguageIsUsed() {
        XCTAssertEqual(policy(["pl"]).plan(from: nil),
                       DecodePolicy.Plan(language: "pl", task: .transcribe))
        XCTAssertEqual(policy(["pl"]).plan(from: scores([:])),
                       DecodePolicy.Plan(language: "pl", task: .transcribe))
    }

    /// Nothing in the app allows an empty selection — one language is always
    /// selected — but the policy should not be the reason if that ever changes.
    func testAnEmptySelectionDoesNotSilentlyBecomeEnglish() {
        let none = DecodePolicy(selected: [], translatesUnsupported: false)
        XCTAssertNil(none.plan(from: nil).language)
        // Nothing to constrain to, so the detected language is better than nil,
        // which WhisperKit would read as English.
        XCTAssertEqual(none.plan(from: scores(["pl": -0.1])),
                       DecodePolicy.Plan(language: "pl", task: .transcribe))
    }
}
