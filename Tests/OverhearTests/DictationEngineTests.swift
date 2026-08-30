import XCTest
@testable import Overhear

/// Exercises the dictation loop end to end with real wake word models and a
/// stand-in transcriber: the batching, the stop rules and what happens when the
/// microphone goes away are the parts worth pinning down, and they don't need
/// Whisper to be real.
///
/// The scenarios come from `Specs/Dictation.md` and `Specs/AudioDevices.md`;
/// the cancel word has its own suite in `CancelWordTests`.
final class DictationEngineTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await EngineTestModels.ensure()
    }

    // MARK: - One utterance at a time

    func testTranscribesABatchAfterAPause() async throws {
        let transcriber = StubTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 1.0)
        harness.audio.sendSilence(seconds: 2.0)

        try await harness.waitFor(.transcription("hello world"))
        let events = await harness.seen()
        XCTAssertTrue(events.contains(.speechStart), "the overlay needs to know speech started")
        XCTAssertTrue(events.contains(.transcribing))
    }

    /// "Nothing is inserted before the pause ends" — a batch is not handed over
    /// while the user is still talking, however long they go on for.
    func testNothingIsTranscribedWhileSpeechContinues() async throws {
        let transcriber = StubTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 1.0)
        try await harness.waitFor(.speechStart)
        try await harness.neverSees(.transcribing, within: .milliseconds(600))

        let unfinished = await transcriber.recorded()
        XCTAssertTrue(unfinished.isEmpty, "no batch may be transcribed until the speaker pauses")

        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcription("hello world"))
    }

    /// Three utterances with pauses between them arrive as three insertions, in
    /// the order they were spoken, each after its own pause.
    func testEachUtteranceIsTranscribedSeparatelyAndInOrder() async throws {
        let transcriber = StubTranscriber(texts: ["first", "second", "third"])
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        for expected in ["first", "second", "third"] {
            harness.audio.sendSpeech(seconds: 0.8)
            harness.audio.sendSilence(seconds: 2.0)
            try await harness.waitFor(.transcription(expected))
        }

        let spoken = await harness.transcriptions()
        XCTAssertEqual(spoken, ["first", "second", "third"])
        let batches = await transcriber.recorded()
        XCTAssertEqual(batches.count, 3, "no utterance may be merged with the next")
    }

    /// A pause shorter than the silence the engine waits for is part of the
    /// utterance, not the end of it — otherwise a long message is chopped up
    /// mid-sentence.
    func testAShortPauseDoesNotEndTheBatch() async throws {
        let transcriber = StubTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 1.0)
        harness.audio.sendSilence(seconds: 1.0)
        harness.audio.sendSpeech(seconds: 1.0)
        harness.audio.sendSilence(seconds: 2.0)

        try await harness.waitFor(.transcription("hello world"))
        try await harness.neverSees(.transcribing, count: 2, within: .milliseconds(400))

        let batches = await transcriber.recorded()
        XCTAssertEqual(batches.count, 1, "a one-second pause is not the end of an utterance")
        let seconds = Double(batches[0].count) / AudioCapture.sampleRate
        XCTAssertGreaterThan(seconds, 3.0, "both halves and the pause between them belong to the batch")
    }

    /// Speech that runs past the batch cap is split rather than held or
    /// discarded: the first thirty seconds are transcribed while the user is
    /// still talking, and what follows lands in the next batch.
    func testSplitsSpeechLongerThanTheBatchCap() async throws {
        let transcriber = StubTranscriber(texts: ["first half", "second half"])
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        await harness.audio.sendPacedSpeech(seconds: 40)

        // Still speaking — no pause has been sent — and text has already
        // arrived.
        try await harness.waitFor(.transcription("first half"))
        let firstBatches = await transcriber.recorded()
        let capped = try XCTUnwrap(firstBatches.first)
        let seconds = Double(capped.count) / AudioCapture.sampleRate
        XCTAssertEqual(seconds, 30.0, accuracy: 0.1, "the first batch is the thirty-second cap")

        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcription("second half"))

        let batches = await transcriber.recorded()
        XCTAssertGreaterThanOrEqual(batches.count, 2, "speech past the cap is transcribed, not dropped")
        XCTAssertFalse(batches[1].isEmpty)
    }

    // MARK: - What is not speech

    /// Silence alone is not a batch. Whisper hallucinates on empty audio, so a
    /// batch that never crossed the speech threshold must never reach it.
    func testDiscardsABatchThatIsAllSilence() async throws {
        let transcriber = StubTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSilence(seconds: 4.0)
        try await Task.sleep(for: .milliseconds(500))

        let batches = await transcriber.recorded()
        XCTAssertTrue(batches.isEmpty, "silence should never be transcribed")
    }

    /// Speech too quiet to cross the level threshold is not a batch either, and
    /// the engine is still listening for one spoken normally straight after.
    func testSpeechBelowTheLevelThresholdIsNotABatch() async throws {
        let transcriber = StubTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.send(samples: try SyntheticSample.quietEn.load())
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.neverSees(.speechStart, within: .milliseconds(400))
        let quiet = await transcriber.recorded()
        XCTAssertTrue(quiet.isEmpty, "a whisper is below the threshold")

        harness.audio.send(samples: try SyntheticSample.helloEn.load())
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcription("hello world"))
        let batches = await transcriber.recorded()
        XCTAssertEqual(batches.count, 1, "only the audible utterance is a batch")
    }

    // MARK: - Stopping

    /// Nothing may reach the user's document after they press Stop — including
    /// a batch that was mid-flight when they did.
    func testDropsAnUnfinishedBatchOnStop() async throws {
        let transcriber = StubTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 1.0)
        try await harness.waitFor(.speechStart)
        await harness.engine.deactivate()
        try await Task.sleep(for: .milliseconds(400))

        let batches = await transcriber.recorded()
        XCTAssertTrue(batches.isEmpty, "an utterance interrupted by Stop is discarded")
    }

    /// The same promise one step later: a transcription that was already
    /// running when Stop was pressed is thrown away rather than pasted.
    func testDropsATranscriptionThatWasAlreadyRunning() async throws {
        let transcriber = GatedTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 1.0)
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcribing)

        await harness.engine.deactivate()
        await transcriber.release()

        try await harness.neverSees(.transcription("hello world"), within: .seconds(1))
    }

    /// Stopping and starting again picks up where it left off rather than
    /// needing the engine rebuilt.
    func testDictationCanBeRestartedAfterStopping() async throws {
        let transcriber = StubTranscriber(texts: ["first", "second"])
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 0.8)
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcription("first"))

        await harness.engine.deactivate()
        try await harness.waitFor(.idle, count: 2)

        await harness.engine.activate()
        harness.audio.sendSpeech(seconds: 0.8)
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcription("second"))
    }

    // MARK: - The microphone

    /// A device disappearing takes dictation down with it rather than leaving
    /// the UI claiming to listen to a microphone that is gone.
    func testLosingTheDeviceReturnsToIdle() async throws {
        let harness = await makeEngineHarness()
        try await activate(harness)

        harness.audio.send(.interrupted("device went away"))

        try await harness.waitFor(.warning("Audio device changed: device went away"))
        try await harness.waitFor(.idle)
    }

    /// Nothing was transcribed from the batch the lost device interrupted.
    func testLosingTheDeviceDiscardsTheUtteranceInProgress() async throws {
        let transcriber = StubTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 1.0)
        try await harness.waitFor(.speechStart)
        harness.audio.send(.interrupted("device went away"))
        try await Task.sleep(for: .milliseconds(400))

        let batches = await transcriber.recorded()
        XCTAssertTrue(batches.isEmpty, "a half-heard utterance is not transcribed")
    }

    /// And once a device is back, dictation works again without the app being
    /// restarted.
    func testDictationWorksAgainOnceTheDeviceReturns() async throws {
        let transcriber = StubTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.send(.interrupted("device went away"))
        try await harness.waitFor(.idle)

        // The device comes back: audio starts arriving again and the user
        // starts dictation for a second time.
        harness.audio.sendSilence(seconds: 0.2)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 0.8)
        harness.audio.sendSilence(seconds: 2.0)
        try await harness.waitFor(.transcription("hello world"))
    }

    /// The engine only calls itself idle once audio is actually arriving — with
    /// no input device it stays loading rather than claiming to be listening.
    func testStaysLoadingUntilAudioArrives() async throws {
        let harness = await makeEngineHarness(primed: false)

        try await harness.waitFor(.status("whisper_ready"))
        try await harness.neverSees(.idle, within: .seconds(1))

        harness.audio.sendSilence(seconds: 0.2)
        try await harness.waitFor(.idle)
    }

    /// Speech that starts the instant dictation does keeps its opening word.
    func testSpeechImmediatelyAfterStartingIsNotClipped() async throws {
        let transcriber = StubTranscriber()
        let harness = await makeEngineHarness(transcriber: transcriber)

        // Let the moment of priming audio drain first, so what the batch starts
        // with is the user's own first chunk and nothing else.
        try await harness.waitFor(.idle)
        try await Task.sleep(for: .milliseconds(60))

        // No waiting for .ready: the user chose Start Listening and began
        // talking straight away.
        await harness.engine.activate()
        let hello = try SyntheticSample.helloEn.load()
        harness.audio.send(samples: hello)
        harness.audio.sendSilence(seconds: 2.0)

        try await harness.waitFor(.transcription("hello world"))
        let batches = await transcriber.recorded()
        let batch = try XCTUnwrap(batches.first)
        XCTAssertEqual(Array(batch.prefix(WakeWordDetector.chunkSamples)),
                       Array(hello.prefix(WakeWordDetector.chunkSamples)),
                       "the batch starts at the first chunk the user spoke")
    }
}
