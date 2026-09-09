import XCTest
@testable import Overhear

/// `Specs/Dictation.md` — the ending hold to talk needs, which no other way out
/// of a session provides.
///
/// Stopping discards: the batch in progress is dropped and a result already
/// running is thrown away. A release cannot do that, because it is how the user
/// says they have finished speaking. So `finish()` is a third state alongside
/// activate and deactivate, and everything here is about the difference.
final class HoldToTalkTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await EngineTestModels.ensure()
    }

    /// The words spoken up to the release arrive, without the pause a batch
    /// would otherwise wait for.
    func testTheReleaseTranscribesWhatWasSaid() async throws {
        let transcriber = StubTranscriber(text: "hello")
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 1.0)
        try await harness.waitFor(.speechStart)
        await harness.engine.finish()

        try await harness.waitFor(.transcription("hello"))
    }

    /// The whole of what separates it from **Stop Listening**, which drops the
    /// same batch on the floor.
    func testStoppingDiscardsWhatAReleaseWouldHaveKept() async throws {
        let transcriber = StubTranscriber(text: "hello")
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 1.0)
        try await harness.waitFor(.speechStart)
        await harness.engine.deactivate()

        try await harness.neverSees(.transcribing, within: .milliseconds(500))
        let batches = await transcriber.recorded()
        XCTAssertTrue(batches.isEmpty, "nothing recorded before a stop reaches the transcriber")
    }

    /// The session ends with the batch it ended, rather than staying up waiting
    /// for a key nobody is holding any more.
    func testDictationIsNotActiveOnceTheInsertionHasArrived() async throws {
        let harness = await makeEngineHarness(transcriber: StubTranscriber(text: "hello"))
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 1.0)
        try await harness.waitFor(.speechStart)
        await harness.engine.finish()
        try await harness.waitFor(.transcription("hello"))
        try await harness.waitFor(.idle, count: 2)

        let ready = await harness.count(of: .ready)
        harness.audio.sendSpeech(seconds: 1.0)
        harness.audio.sendSilence(seconds: 2.0)
        try await Task.sleep(for: .milliseconds(500))

        let readyAfter = await harness.count(of: .ready)
        let transcribed = await harness.transcriptions()
        XCTAssertEqual(readyAfter, ready, "speaking after the release starts nothing")
        XCTAssertEqual(transcribed.count, 1, "and transcribes nothing")
    }

    /// There is no minimum hold. A tap is a session with silence in it, and
    /// silence already produces nothing.
    func testATapWithNoSpeechInItProducesNothing() async throws {
        let harness = await makeEngineHarness(transcriber: StubTranscriber(text: "hello"))
        try await activate(harness)

        harness.audio.sendSilence(seconds: 0.2)
        await harness.engine.finish()
        try await harness.waitFor(.idle, count: 2)

        let transcribed = await harness.transcriptions()
        XCTAssertEqual(transcribed, [], "a stray tap leaves nothing behind")
        try await harness.neverSees(.transcribing, within: .milliseconds(300))
    }

    /// Two holds are two utterances, in the order they were spoken, neither
    /// merged with the next.
    func testEachHoldIsItsOwnUtterance() async throws {
        let transcriber = StubTranscriber(texts: ["first", "second"])
        let harness = await makeEngineHarness(transcriber: transcriber)

        for expected in ["first", "second"] {
            try await activate(harness)
            harness.audio.sendSpeech(seconds: 0.8)
            try await harness.waitFor(.speechStart, count: expected == "first" ? 1 : 2)
            await harness.engine.finish()
            try await harness.waitFor(.transcription(expected))
        }

        let transcribed = await harness.transcriptions()
        XCTAssertEqual(transcribed, ["first", "second"])
    }

    /// A second press and release arriving while the first batch is still in
    /// Whisper does not cancel it — the utterance the user has already finished
    /// still arrives.
    func testAReleaseDuringTranscriptionDoesNotCancelTheOneRunning() async throws {
        let transcriber = GatedTranscriber(text: "hello")
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 1.0)
        try await harness.waitFor(.speechStart)
        await harness.engine.finish()
        try await harness.waitFor(.transcribing)

        // The engine is still dictating until the batch lands, so a release
        // reaching it here must not turn into a discard.
        await harness.engine.finish()
        await transcriber.release()

        try await harness.waitFor(.transcription("hello"))
    }

    /// Stopping discards, whichever mode it happens in — and the release that
    /// follows it has nothing left to end.
    func testAReleaseAfterStoppingStartsNothing() async throws {
        let harness = await makeEngineHarness(transcriber: StubTranscriber(text: "hello"))
        try await activate(harness)

        harness.audio.sendSpeech(seconds: 1.0)
        try await harness.waitFor(.speechStart)
        await harness.engine.deactivate()
        await harness.engine.finish()

        let ready = await harness.count(of: .ready)
        harness.audio.sendSpeech(seconds: 1.0)
        harness.audio.sendSilence(seconds: 2.0)
        try await Task.sleep(for: .milliseconds(500))

        let readyAfter = await harness.count(of: .ready)
        let transcribed = await harness.transcriptions()
        XCTAssertEqual(readyAfter, ready, "letting go does not start a session")
        XCTAssertEqual(transcribed, [], "and does not transcribe what was said before the stop")
    }

    /// A release during a device change ends the intention to dictate with it.
    /// Otherwise the device coming back would resume a session under a key that
    /// has already been let go of — one nothing could then end.
    func testAReleaseWhileTheDeviceIsAwayIsRespected() async throws {
        let harness = await makeEngineHarness()
        try await activate(harness)

        harness.audio.send(.interrupted("device went away"))
        // The second idle: the first is the engine reporting itself ready at
        // launch, and waiting for that one would race the interruption.
        try await harness.waitFor(.idle, count: 2)
        await harness.engine.finish()

        let ready = await harness.count(of: .ready)
        harness.audio.sendSilence(seconds: 0.5)
        try await Task.sleep(for: .milliseconds(500))

        let readyAfter = await harness.count(of: .ready)
        XCTAssertEqual(readyAfter, ready, "the release outranks the resumption")
    }

    /// Speech that runs past the batch cap is transcribed as it goes, hold or
    /// no hold: the release ends the batch being recorded, not the session's
    /// first batch.
    func testALongHoldStillSplitsAtTheCap() async throws {
        let transcriber = StubTranscriber(texts: ["first", "second"])
        let harness = await makeEngineHarness(transcriber: transcriber)
        try await activate(harness)

        await harness.audio.sendPacedSpeech(seconds: 31.0)
        try await harness.waitFor(.transcription("first"))

        await harness.engine.finish()
        try await harness.waitFor(.transcription("second"))
    }
}
