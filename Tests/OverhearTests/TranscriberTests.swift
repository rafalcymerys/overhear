import AVFoundation
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

        let audio = try loadFixture("unrelated_speech")
        let result = try await transcriber.transcribe(audio, languages: ["en"])

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
            try loadFixture("unrelated_speech"),
            languages: ["en", "pl"]
        )
        XCTAssertEqual(english.language, "en")

        let polish = try await transcriber.transcribe(
            try loadFixture("polish_speech"),
            languages: ["en", "pl"]
        )
        XCTAssertEqual(polish.language, "pl", "Polish must not be read as the alphabetically first language")
        XCTAssertTrue(
            polish.text.lowercased().contains("dobry"),
            "expected Polish words back, got: \(polish.text)"
        )
    }

    private func loadFixture(_ name: String) throws -> [Float] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "wav"))
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        return (0..<Int(buffer.frameLength)).map { channel[$0] }
    }
}
