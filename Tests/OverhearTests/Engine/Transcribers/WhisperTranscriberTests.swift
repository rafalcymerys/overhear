import XCTest
@testable import Overhear

/// Proves the WhisperKit wiring for real — the model actually loads, the audio
/// format we hand it is one it accepts, and words come back.
///
/// Skipped by default: the first run downloads and compiles a few hundred
/// megabytes of CoreML model. Run it with
/// `OVERHEAR_RUN_MODEL_TESTS=1 swift test --filter WhisperTranscriberTests`.
final class WhisperTranscriberTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OVERHEAR_RUN_MODEL_TESTS"] == "1",
            "set OVERHEAR_RUN_MODEL_TESTS=1 to run tests that download Whisper"
        )
    }

    func testTranscribesSpeech() async throws {
        let transcriber = WhisperTranscriber()
        try await transcriber.load()

        let audio = try SyntheticSample.sentenceEn.load()
        let result = try await transcriber.transcribe(audio, languages: ["en"], translatesUnsupported: false)

        let text = result.text.lowercased()
        XCTAssertTrue(text.contains("quick"), "expected the fixture's words, got: \(result.text)")
        XCTAssertTrue(text.contains("lazy"), "expected the fixture's words, got: \(result.text)")
        XCTAssertEqual(result.language, "en")
    }

    /// The default setup is English plus Polish, so detection has to actually
    /// tell them apart — not merely return whichever is listed first.
    func testDetectsWhichOfTheSelectedLanguagesWasSpoken() async throws {
        let transcriber = WhisperTranscriber()
        try await transcriber.load()

        let english = try await transcriber.transcribe(
            try SyntheticSample.sentenceEn.load(),
            languages: ["en", "pl"],
            translatesUnsupported: false
        )
        XCTAssertEqual(english.language, "en")

        let polish = try await transcriber.transcribe(
            try SyntheticSample.sentencePl.load(),
            languages: ["en", "pl"],
            translatesUnsupported: false
        )
        XCTAssertEqual(polish.language, "pl", "Polish must not be read as the alphabetically first language")
        XCTAssertTrue(
            polish.text.lowercased().contains("dobry"),
            "expected Polish words back, got: \(polish.text)"
        )
        // R-98: the failure was Polish speech coming back as English, so assert
        // the absence of the translation as well as the presence of the Polish.
        for english in ["good morning", "hello", "speech recognition"] {
            XCTAssertFalse(
                polish.text.lowercased().contains(english),
                "Polish was translated to English: \(polish.text)"
            )
        }
    }

    /// R-98 as reported: Polish speech with Polish selected must come back
    /// Polish. `base` scores this clip pl=23.2 against en=15.5, so honouring the
    /// ranking is what keeps it Polish.
    func testSelectedLanguagesWinOverTheAlternatives() async throws {
        let transcriber = WhisperTranscriber()
        try await transcriber.load()

        let result = try await transcriber.transcribe(
            try SyntheticSample.sentencePl.load(),
            languages: ["en", "pl"],
            translatesUnsupported: false
        )

        XCTAssertEqual(result.language, "pl")
        XCTAssertFalse(
            result.text.lowercased().contains("good"),
            "Polish came back as English: \(result.text)"
        )
    }

    /// A language the user selected is transcribed as itself even when another
    /// language is a plausible reading of the audio.
    func testAnUnselectedLanguageDoesNotWinOverASelectedOne() async throws {
        let transcriber = WhisperTranscriber()
        try await transcriber.load()

        let result = try await transcriber.transcribe(
            try SyntheticSample.gutenTagDe.load(),
            languages: ["en", "de"],
            translatesUnsupported: false
        )

        XCTAssertEqual(result.language, "de")
        XCTAssertTrue(
            result.text.lowercased().contains("guten tag"),
            "expected German back, got: \(result.text)"
        )
    }

    /// With only English selected, German stays inside the configuration rather
    /// than producing German text — selecting a language has to mean something.
    func testOutputStaysInsideTheSelectedLanguages() async throws {
        let transcriber = WhisperTranscriber()
        try await transcriber.load()

        let result = try await transcriber.transcribe(
            try SyntheticSample.gutenTagDe.load(),
            languages: ["en"],
            translatesUnsupported: false
        )

        XCTAssertEqual(result.language, "en", "output should stay in the one selected language")
    }

    /// Turning translation on is the one case where output leaves the selected
    /// languages: the batch is decoded as what was actually spoken, translated.
    func testTranslationLeavesTheSelectedLanguages() async throws {
        let transcriber = WhisperTranscriber()
        try await transcriber.load()

        let result = try await transcriber.transcribe(
            try SyntheticSample.gutenTagDe.load(),
            languages: ["en"],
            translatesUnsupported: true
        )

        XCTAssertEqual(result.language, "de", "translation decodes the language actually spoken")
        XCTAssertTrue(
            result.text.lowercased().contains("good day"),
            "expected an English translation, got: \(result.text)"
        )
    }

    /// Selecting one language and speaking it is the ordinary case, and it has
    /// to work without English anywhere in the configuration.
    func testASingleSelectedLanguageIsTranscribedAsItself() async throws {
        let transcriber = WhisperTranscriber()
        try await transcriber.load()

        let result = try await transcriber.transcribe(
            try SyntheticSample.sentencePl.load(),
            languages: ["pl"],
            translatesUnsupported: false
        )

        XCTAssertEqual(result.language, "pl")
        XCTAssertTrue(
            result.text.lowercased().contains("dobry"),
            "expected Polish back, got: \(result.text)"
        )
    }

    /// R-98 was intermittent — the same phrase came back English some of the
    /// time — so one pass proves less than a handful of them.
    func testPolishStaysPolishAcrossRepeatedUtterances() async throws {
        let transcriber = WhisperTranscriber()
        try await transcriber.load()

        let audio = try SyntheticSample.dzienDobryPl.load()
        for attempt in 1...5 {
            let result = try await transcriber.transcribe(
                audio,
                languages: ["en", "pl"],
                translatesUnsupported: false
            )
            XCTAssertEqual(result.language, "pl", "attempt \(attempt) left Polish")
            for english in ["good morning", "good day", "hello"] {
                XCTAssertFalse(
                    result.text.lowercased().contains(english),
                    "attempt \(attempt) came back English: \(result.text)"
                )
            }
        }
    }

    /// The translation setting governs languages the user did not select. One
    /// they did select is transcribed as itself whatever it says.
    func testTranslationDoesNotTouchASelectedLanguage() async throws {
        let transcriber = WhisperTranscriber()
        try await transcriber.load()

        let result = try await transcriber.transcribe(
            try SyntheticSample.sentencePl.load(),
            languages: ["en", "pl"],
            translatesUnsupported: true
        )

        XCTAssertEqual(result.language, "pl")
        XCTAssertTrue(
            result.text.lowercased().contains("dobry"),
            "Polish was translated despite being selected: \(result.text)"
        )
    }

    /// Speech in a language the user did not select comes back in one they did
    /// — whichever the model scores higher, not a fixed one of the two.
    func testAnUnselectedLanguageIsDecodedAsOneOfTheSelectedOnes() async throws {
        let transcriber = WhisperTranscriber()
        try await transcriber.load()

        let result = try await transcriber.transcribe(
            try SyntheticSample.bonjourFr.load(),
            languages: ["en", "pl"],
            translatesUnsupported: false
        )

        let language = try XCTUnwrap(result.language)
        XCTAssertTrue(["en", "pl"].contains(language), "output left the selected languages: \(language)")
        XCTAssertFalse(result.text.isEmpty)
    }

    /// An utterance that switches language halfway is still one utterance: one
    /// transcription, in one of the languages selected.
    func testAnUtteranceInTwoLanguagesComesBackAsOne() async throws {
        let transcriber = WhisperTranscriber()
        try await transcriber.load()

        let result = try await transcriber.transcribe(
            try SyntheticSample.mixedEnPl.load(),
            languages: ["en", "pl"],
            translatesUnsupported: false
        )

        let language = try XCTUnwrap(result.language)
        XCTAssertTrue(["en", "pl"].contains(language))
        XCTAssertFalse(result.text.isEmpty, "the utterance should not come back empty")
    }

    // MARK: - What comes back that is not speech

    /// R-97 against the real model: a cough is described rather than
    /// transcribed, and the description is what the filter exists to remove.
    func testNonSpeechComesBackAsAnAnnotationTheFilterRemoves() async throws {
        let transcriber = WhisperTranscriber()
        try await transcriber.load()

        let result = try await transcriber.transcribe(
            try SyntheticSample.coughing.load(),
            languages: ["en"],
            translatesUnsupported: false
        )

        let spoken = AnnotationFilter(stripsParentheses: true).filter(result.text)
        XCTAssertTrue(spoken.isEmpty, "a cough should leave nothing to paste, got: \(result.text)")
    }

    /// Ordinary dictation keeps its punctuation and casing on the way through —
    /// the filter is aimed at annotations, not at sentences.
    func testOrdinarySpeechKeepsItsPunctuation() async throws {
        let transcriber = WhisperTranscriber()
        try await transcriber.load()

        let result = try await transcriber.transcribe(
            try SyntheticSample.paragraphEn.load(),
            languages: ["en"],
            translatesUnsupported: false
        )

        XCTAssertTrue(result.text.contains("."), "expected sentences, got: \(result.text)")
        XCTAssertTrue(result.text.contains(where: \.isUppercase), "expected casing, got: \(result.text)")
        XCTAssertEqual(AnnotationFilter(stripsParentheses: true).filter(result.text), result.text,
                       "nothing in ordinary dictation looks like an annotation")
    }
}
