import XCTest
@testable import Overhear

/// Proves the WhisperKit wiring for real — the model actually loads, the audio
/// format we hand it is one it accepts, and words come back.
///
/// Skipped by default: the first run downloads and compiles a few hundred
/// megabytes of CoreML model. Run it with
/// `OVERHEAR_RUN_MODEL_TESTS=1 swift test --filter TranscriberTests`.
final class TranscriberTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OVERHEAR_RUN_MODEL_TESTS"] == "1",
            "set OVERHEAR_RUN_MODEL_TESTS=1 to run tests that download Whisper"
        )
    }

    func testTranscribesSpeech() async throws {
        let transcriber = Transcriber()
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
        let transcriber = Transcriber()
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
        let transcriber = Transcriber()
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
        let transcriber = Transcriber()
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
        let transcriber = Transcriber()
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
        let transcriber = Transcriber()
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

}
