import XCTest
@testable import Overhear

/// Speech that falls below the level that starts a batch: the end of a
/// sentence trailing off, or quiet audio before one. Neither may be held back
/// and pasted with whatever is said next.
final class QuietSpeechTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await EngineTestModels.ensure()
    }

    /// A sentence that trails off below the level that starts speech. The
    /// quiet tail is still the sentence, so it stays in that batch rather than
    /// ending it early and waiting in the next one, to be stitched onto
    /// whatever is said after a break.
    func testAQuietTailIsNotCarriedIntoTheNextUtterance() async throws {
        let transcriber = StubTranscriber(texts: ["first", "second"])
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 1.0)
        harness.audio.send(samples: Self.quiet(seconds: 3.0))
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcription("first"))

        harness.audio.sendSpeech(seconds: 1.0)
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcription("second"))

        let batches = await transcriber.recorded()
        XCTAssertEqual(batches.count, 2)
        let first = Double(batches[0].count) / AudioCapture.sampleRate
        XCTAssertGreaterThan(first, 5.0, "the whole quiet tail belongs to the sentence it ends")
        let second = Double(batches[1].count) / AudioCapture.sampleRate
        XCTAssertLessThan(second, 3.5,
                          "the second batch is its own speech and pause, not the first one's leftovers")
    }

    /// Audio below the speech level before an utterance is not kept beyond a
    /// short pre-roll, however long it went on — otherwise it is transcribed
    /// with the next thing said, long after it was heard.
    func testAudioBeforeSpeechIsOnlyKeptAsAPreRoll() async throws {
        let transcriber = StubTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.send(samples: Self.quiet(seconds: 3.0))
        harness.audio.sendSilence(seconds: 2.0)
        harness.audio.sendSpeech(seconds: 1.0)
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcription("hello world"))

        let batches = await transcriber.recorded()
        XCTAssertEqual(batches.count, 1)
        let seconds = Double(batches[0].count) / AudioCapture.sampleRate
        let expected = BatchRules.preRollDuration + 1.0 + BatchRules.silenceDuration
        XCTAssertEqual(seconds, expected, accuracy: 0.2,
                       "the pre-roll, the speech and the pause that ended it — nothing older")
    }

    /// A tone just under the speech threshold: audible, but not speech by
    /// `BatchRules.isSilent`.
    private static func quiet(seconds: Double) -> [Float] {
        ScriptedAudioSource.speech(seconds: seconds).map { $0 / 0.3 * 0.01 }
    }
}
