import XCTest
@testable import Overhear

/// Proves the FluidAudio wiring for real — the models load from where the
/// service put them, the audio format the engine hands over is one Parakeet
/// accepts, and words come back.
///
/// Skipped by default: the first run downloads and compiles about half a
/// gigabyte of CoreML model. Run it with
/// `OVERHEAR_RUN_MODEL_TESTS=1 swift test --filter ParakeetTranscriberTests`.
final class ParakeetTranscriberTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OVERHEAR_RUN_MODEL_TESTS"] == "1",
            "set OVERHEAR_RUN_MODEL_TESTS=1 to run tests that download Parakeet"
        )
    }

    /// Fetches the weights the way the app does, so the test exercises the same
    /// directory layout the transcriber reads from rather than FluidAudio's own
    /// cache.
    private func loadedTranscriber(
        _ model: TranscriptionModel = ModelCatalog.parakeetV3
    ) async throws -> ParakeetTranscriber {
        let service = await TranscriptionModelService()
        await service.startDownload(model)
        while await service.isDownloading(model) {
            try await Task.sleep(for: .milliseconds(200))
        }
        let downloaded = await service.isDownloaded(model)
        try XCTSkipUnless(downloaded, "\(model.displayName) could not be downloaded")

        let transcriber = ParakeetTranscriber(model: model)
        try await transcriber.load()
        return transcriber
    }

    func testTranscribesSpeech() async throws {
        let transcriber = try await loadedTranscriber()

        let audio = try SyntheticSample.sentenceEn.load()
        let start = Date()
        let result = try await transcriber.transcribe(audio, languages: ["en"], translatesUnsupported: false)
        let elapsed = Date().timeIntervalSince(start)

        let text = result.text.lowercased()
        XCTAssertTrue(text.contains("quick"), "expected the fixture's words, got: \(result.text)")
        XCTAssertTrue(text.contains("lazy"), "expected the fixture's words, got: \(result.text)")

        // Not an assertion — the number this suite exists to produce. A batch
        // has to come back before the user has finished their next sentence.
        print("Parakeet v3: \(String(format: "%.2f", elapsed))s for \(String(format: "%.1f", Double(audio.count) / 16000))s of audio")
    }

    /// R-98, in a second engine: Polish speech must not come back as English.
    func testPolishStaysPolish() async throws {
        let transcriber = try await loadedTranscriber()

        let audio = try SyntheticSample.sentencePl.load()
        let result = try await transcriber.transcribe(audio, languages: ["pl"], translatesUnsupported: false)

        XCTAssertFalse(result.text.isEmpty, "the utterance was dropped as the wrong language")
        XCTAssertFalse(result.text.lowercased().contains("good morning"),
                       "expected Polish, got: \(result.text)")
    }

    /// The check that makes the language selection mean something for an engine
    /// that cannot be constrained: speech outside the selection is dropped
    /// rather than pasted.
    func testSpeechOutsideTheSelectedLanguagesIsDropped() async throws {
        let transcriber = try await loadedTranscriber()

        let audio = try SyntheticSample.sentencePl.load()
        let result = try await transcriber.transcribe(audio, languages: ["en"], translatesUnsupported: false)

        XCTAssertTrue(result.text.isEmpty,
                      "Polish reached a document belonging to someone who selected English: \(result.text)")
    }

    /// A batch too short for the model comes back empty rather than throwing —
    /// the engine treats empty as nothing having been said, and a throw would
    /// put a failure in the menu bar for a cough.
    func testTooShortAnUtteranceIsEmptyRatherThanAnError() async throws {
        let transcriber = try await loadedTranscriber()

        let result = try await transcriber.transcribe(Array(repeating: 0, count: 1600),
                                                      languages: ["en"],
                                                      translatesUnsupported: false)
        XCTAssertTrue(result.text.isEmpty)
    }

    /// Longer than FluidAudio's own fifteen-second window, which the thirty
    /// second batch cap can produce. The chunking that covers it is inside the
    /// single call, so this is the test that it happens at all.
    func testAnUtteranceLongerThanTheModelsWindow() async throws {
        let transcriber = try await loadedTranscriber()

        let sentence = try SyntheticSample.sentenceEn.load()
        var audio: [Float] = []
        while audio.count < 16000 * 18 {
            audio += sentence
        }

        let result = try await transcriber.transcribe(audio, languages: ["en"], translatesUnsupported: false)
        XCTAssertFalse(result.text.isEmpty, "nothing came back from a long batch")
    }

    /// The English-only build is the one the pane narrows the language
    /// selection for.
    func testTheEnglishOnlyModelTranscribesEnglish() async throws {
        let transcriber = try await loadedTranscriber(ModelCatalog.parakeetV2)

        let audio = try SyntheticSample.sentenceEn.load()
        let result = try await transcriber.transcribe(audio, languages: ["en"], translatesUnsupported: false)

        XCTAssertTrue(result.text.lowercased().contains("quick"),
                      "expected the fixture's words, got: \(result.text)")
    }
}
