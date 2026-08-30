import XCTest
@testable import Overhear

/// `Specs/CancelWord.md`, driven through the real wake word models.
///
/// Saying the cancel word has to discard whatever is being heard *or*
/// transcribed and leave dictation running, which is three different code paths
/// depending on how far the batch has got: mid-utterance, in the backlog that
/// piled up while Whisper ran, and after the engine has already been cancelled
/// once.
final class CancelWordTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await EngineTestModels.ensure()
    }

    // MARK: - While the user is speaking

    /// The cancel word mid-utterance drops the batch, and dictation carries on:
    /// the next thing said is transcribed as usual.
    func testCancelsAnUtteranceInProgressAndKeepsListening() async throws {
        let transcriber = StubTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 0.5)
        harness.audio.send(samples: try SyntheticSample.alexa.load())

        try await harness.waitFor(.wakeWordCancel)
        let cancelled = await transcriber.recorded()
        XCTAssertTrue(cancelled.isEmpty, "the cancelled batch must not be transcribed")

        harness.audio.send(samples: try SyntheticSample.helloEn.load())
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcription("hello world"))
        let batches = await transcriber.recorded()
        XCTAssertEqual(batches.count, 1, "only the utterance after the cancel is a batch")
    }

    /// The cancel word at the very end of a sentence, with no pause before it,
    /// still cancels — `SentenceThenAlexa` is that sentence.
    func testCancelsAtTheEndOfAnUtterance() async throws {
        let transcriber = StubTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.send(samples: try SyntheticSample.sentenceThenAlexa.load())
        harness.audio.sendSilence(seconds: 2.0)

        try await harness.waitFor(.wakeWordCancel)
        let batches = await transcriber.recorded()
        XCTAssertTrue(batches.isEmpty, "the sentence goes with the cancel word")
    }

    /// Each cancel word in a row is heard: the detector is reset after every
    /// one, so the second and third are not swallowed by the first.
    func testEveryRepeatedCancelWordFires() async throws {
        let transcriber = StubTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        for round in 1...3 {
            harness.audio.sendSpeech(seconds: 0.5)
            harness.audio.send(samples: try SyntheticSample.alexa.load())
            try await harness.waitFor(.wakeWordCancel, count: round)
        }

        let batches = await transcriber.recorded()
        XCTAssertTrue(batches.isEmpty, "every one of them is discarded")
        // Still dictating: the loop announces itself ready after each cancel.
        let readies = await harness.count(of: .ready)
        XCTAssertGreaterThanOrEqual(readies, 4)
    }

    // MARK: - While Whisper is running

    /// A cancel word spoken while the batch is being transcribed lands in the
    /// backlog rather than in the batch, and has to be caught there — this is
    /// what makes cancelling work right up until the paste.
    func testCancelsWhileTranscriptionIsRunning() async throws {
        let transcriber = GatedTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 1.0)
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcribing)

        // Said after the pause, while Whisper still has the batch.
        harness.audio.sendSpeech(seconds: 0.5)
        harness.audio.send(samples: try SyntheticSample.alexa.load())
        await transcriber.release()

        try await harness.waitFor(.wakeWordCancel)
        try await harness.neverSees(.transcription("hello world"), within: .milliseconds(600))
    }

    /// Cancelling must not cost the user the sentence they start straight
    /// afterwards.
    func testTheUtteranceAfterACancelIsNotLost() async throws {
        let transcriber = GatedTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 1.0)
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcribing)

        harness.audio.sendSpeech(seconds: 0.5)
        harness.audio.send(samples: try SyntheticSample.alexa.load())
        await transcriber.release()
        try await harness.waitFor(.wakeWordCancel)

        let hello = try SyntheticSample.helloEn.load()
        harness.audio.send(samples: hello)
        harness.audio.sendSilence(seconds: 2.0)
        await transcriber.release()

        try await harness.waitFor(.transcription("hello world"))
        let batches = await transcriber.recorded()
        XCTAssertEqual(batches.count, 2, "the cancelled batch and then the new one")
        XCTAssertTrue(chunks(of: batches[1]).contains(firstChunk(of: hello)),
                      "the new utterance keeps its opening word")
    }

    /// The other half of the same mechanism: speech heard while Whisper was
    /// running, with no cancel word in it, goes back on the queue instead of
    /// being thrown away.
    func testSpeechHeardDuringTranscriptionSurvivesIntoTheNextBatch() async throws {
        let transcriber = GatedTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 1.0)
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcribing)

        let hello = try SyntheticSample.helloEn.load()
        harness.audio.send(samples: hello)
        await transcriber.release()

        harness.audio.sendSilence(seconds: 2.0)
        await transcriber.release()

        try await harness.waitFor(.transcription("hello world"), count: 2)
        let batches = await transcriber.recorded()
        XCTAssertEqual(batches.count, 2)
        XCTAssertTrue(chunks(of: batches[1]).contains(firstChunk(of: hello)),
                      "audio heard during transcription belongs to the next batch")
    }

    // MARK: - When it must not fire

    /// Ordinary speech, in either of the selected languages, is not a cancel
    /// word — the whole feature is worthless if it fires on its own.
    func testOrdinarySpeechDoesNotCancel() async throws {
        let transcriber = StubTranscriber(texts: ["english", "polish"])
        let harness = await makeEngineHarness(transcriber: transcriber, languages: ["en", "pl"])
        try await activate(harness)

        await harness.audio.sendPaced(samples: try SyntheticSample.paragraphEn.load())
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcription("english"))

        await harness.audio.sendPaced(samples: try SyntheticSample.sentencePl.load())
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcription("polish"))

        let cancels = await harness.count(of: .wakeWordCancel)
        XCTAssertEqual(cancels, 0, "neither utterance is a cancel word")
    }

    /// With dictation stopped nothing is listening for the word, so saying it
    /// does nothing at all.
    func testTheCancelWordIsInertWhileDictationIsStopped() async throws {
        let harness = await makeEngineHarness()
        try await harness.waitFor(.idle)

        harness.audio.send(samples: try SyntheticSample.alexa.load())

        try await harness.neverSees(.wakeWordCancel, within: .seconds(1))
        try await harness.neverSees(.ready, within: .milliseconds(200))
    }

    // MARK: - Choosing a different word

    /// Selecting another word swaps which one cancels: the new word does, and
    /// the old one becomes ordinary speech.
    func testAnotherWordCanBeTheCancelWord() async throws {
        let jarvis = HotWord.builtIn[1]
        XCTAssertEqual(jarvis.displayName, "Hey Jarvis")

        let transcriber = StubTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber, cancelWord: jarvis)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 0.5)
        harness.audio.send(samples: try SyntheticSample.heyJarvis.load())
        try await harness.waitFor(.wakeWordCancel)
        let cancelled = await transcriber.recorded()
        XCTAssertTrue(cancelled.isEmpty)

        // Alexa is now just a word, and the utterance containing it is
        // transcribed.
        harness.audio.sendSpeech(seconds: 0.5)
        harness.audio.send(samples: try SyntheticSample.alexa.load())
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcription("hello world"))
        let cancels = await harness.count(of: .wakeWordCancel)
        XCTAssertEqual(cancels, 1, "Alexa no longer cancels")
    }

    // MARK: - Helpers

    private func chunks(of audio: [Float]) -> [[Float]] {
        stride(from: 0, to: audio.count - WakeWordDetector.chunkSamples + 1, by: WakeWordDetector.chunkSamples)
            .map { Array(audio[$0..<($0 + WakeWordDetector.chunkSamples)]) }
    }

    private func firstChunk(of audio: [Float]) -> [Float] {
        Array(audio.prefix(WakeWordDetector.chunkSamples))
    }
}
