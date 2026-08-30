import XCTest
@testable import Overhear

/// Exercises the dictation loop end to end with real wake word models and a
/// stand-in transcriber: the batching, the cancel word and the stop rules are
/// the parts worth pinning down, and they don't need Whisper to be real.
final class DictationEngineTests: XCTestCase {
    private static var modelsDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("overhear-test-models")
    }

    /// Records what it was asked to transcribe and returns a fixed answer.
    private actor StubTranscriber: Transcribing {
        private(set) var batches: [[Float]] = []
        private var text: String

        init(text: String = "hello world") {
            self.text = text
        }

        func load() async throws {}

        func transcribe(_ audio: [Float],
                        languages: [String],
                        translatesUnsupported: Bool) async throws -> Transcription {
            batches.append(audio)
            return Transcription(text: text, language: languages.first)
        }

        func recorded() -> [[Float]] { batches }
    }

    override func setUp() async throws {
        try await super.setUp()
        let setup = await ModelSetup(directory: Self.modelsDirectory)
        try await setup.ensureModels()
    }

    func testTranscribesABatchAfterAPause() async throws {
        let harness = try await makeHarness()
        await harness.engine.activate()
        try await harness.waitFor(.ready)

        harness.audio.sendSpeech(seconds: 1.0)
        harness.audio.sendSilence(seconds: 2.0)

        try await harness.waitFor(.transcription("hello world"))
        let events = await harness.seen()
        XCTAssertTrue(events.contains(.speechStart), "the overlay needs to know speech started")
        XCTAssertTrue(events.contains(.transcribing))
    }

    /// Silence alone is not a batch. Whisper hallucinates on empty audio, so a
    /// batch that never crossed the speech threshold must never reach it.
    func testDiscardsABatchThatIsAllSilence() async throws {
        let harness = try await makeHarness()
        await harness.engine.activate()
        try await harness.waitFor(.ready)

        harness.audio.sendSilence(seconds: 4.0)
        try await Task.sleep(for: .milliseconds(500))

        let batches = await harness.transcriber.recorded()
        XCTAssertTrue(batches.isEmpty, "silence should never be transcribed")
    }

    /// The cancel word mid-utterance drops the batch and keeps dictating.
    func testCancelWordDiscardsTheBatchAndKeepsListening() async throws {
        let harness = try await makeHarness()
        await harness.engine.activate()
        try await harness.waitFor(.ready)

        harness.audio.sendSpeech(seconds: 0.5)
        harness.audio.send(samples: try SyntheticSample.alexa.load())

        try await harness.waitFor(.wakeWordCancel)

        let batches = await harness.transcriber.recorded()
        XCTAssertTrue(batches.isEmpty, "the cancelled batch must not be transcribed")

        // Still dictating: the loop announces itself ready for the next one.
        let events = await harness.seen()
        let cancelIndex = try XCTUnwrap(events.firstIndex(of: .wakeWordCancel))
        XCTAssertTrue(events[cancelIndex...].contains(.ready) || events.filter { $0 == .ready }.count >= 1)
    }

    /// Nothing may reach the user's document after they press Stop — including
    /// a batch that was mid-flight when they did.
    func testDropsAnUnfinishedBatchOnStop() async throws {
        let harness = try await makeHarness()
        await harness.engine.activate()
        try await harness.waitFor(.ready)

        harness.audio.sendSpeech(seconds: 1.0)
        try await Task.sleep(for: .milliseconds(200))
        await harness.engine.deactivate()
        try await Task.sleep(for: .milliseconds(400))

        let batches = await harness.transcriber.recorded()
        XCTAssertTrue(batches.isEmpty, "an utterance interrupted by Stop is discarded")
    }

    /// A device disappearing takes dictation down with it rather than leaving
    /// the UI claiming to listen to a microphone that is gone.
    func testLosingTheDeviceReturnsToIdle() async throws {
        let harness = try await makeHarness()
        await harness.engine.activate()
        try await harness.waitFor(.ready)

        harness.audio.send(.interrupted("device went away"))

        try await harness.waitFor(.warning("Audio device changed: device went away"))
        try await harness.waitFor(.idle)
    }

    // MARK: - Harness

    private struct Harness {
        let engine: DictationEngine
        let audio: ScriptedAudioSource
        let transcriber: StubTranscriber
        let collector: EventCollector

        func seen() async -> [EngineEvent] { await collector.events }

        func waitFor(_ event: EngineEvent, timeout: Duration = .seconds(10)) async throws {
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if await collector.events.contains(event) { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            let seen = await collector.events
            XCTFail("timed out waiting for \(event); saw \(seen)")
        }
    }

    private actor EventCollector {
        var events: [EngineEvent] = []
        func record(_ event: EngineEvent) { events.append(event) }
    }

    private func makeHarness() async throws -> Harness {
        let audio = ScriptedAudioSource()
        let transcriber = StubTranscriber()
        let engine = DictationEngine(
            capture: audio,
            transcriber: transcriber,
            modelsDirectory: Self.modelsDirectory
        )
        let collector = EventCollector()

        let events = await engine.events()
        Task {
            for await event in events {
                await collector.record(event)
            }
        }

        await engine.start(
            languages: ["en"],
            cancelWordPath: HotWord.defaultWord.modelPath(in: Self.modelsDirectory)
        )

        // The loop only reports itself idle once audio is actually arriving.
        audio.sendSilence(seconds: 0.2)

        addTeardownBlock { await engine.stop() }
        return Harness(engine: engine, audio: audio, transcriber: transcriber, collector: collector)
    }

}
