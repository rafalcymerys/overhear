import Foundation
import XCTest
@testable import Overhear

/// The wake word models the engine tests run against.
///
/// Shared across suites and across runs — six files, ~6MB, and fetching them
/// per test class would dominate the suite.
enum EngineTestModels {
    static var directory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("overhear-test-models")
    }

    static func ensure() async throws {
        let setup = await WakeWordSetup(directory: directory)
        try await setup.ensureModels()
    }
}

/// Records what it was asked to transcribe and answers with fixed text.
///
/// `texts` is consumed one entry per batch, so a test that dictates three times
/// can tell the three results apart; the last entry is repeated once they run
/// out.
actor StubTranscriber: Transcribing {
    /// What the engine asked for alongside the audio.
    struct Request: Equatable {
        var languages: [String]
        var translatesUnsupported: Bool
    }

    private let texts: [String]
    private var batches: [[Float]] = []
    private var requests: [Request] = []

    init(text: String = "hello world") {
        self.texts = [text]
    }

    init(texts: [String]) {
        self.texts = texts.isEmpty ? ["hello world"] : texts
    }

    func load() async throws {}

    func transcribe(_ audio: [Float],
                    languages: [String],
                    translatesUnsupported: Bool) async throws -> Transcription {
        batches.append(audio)
        requests.append(Request(languages: languages, translatesUnsupported: translatesUnsupported))
        let text = texts[min(batches.count - 1, texts.count - 1)]
        return Transcription(text: text, language: languages.first)
    }

    func recorded() -> [[Float]] { batches }
    func recordedRequests() -> [Request] { requests }
}

/// A transcriber that stays inside `transcribe(...)` until the test lets it out.
///
/// The only way to exercise what the engine does with audio that arrives *while*
/// Whisper is running: the cancel word found in the backlog, the speech that has
/// to survive to the next batch, and the result that must be dropped when the
/// user stops mid-transcription.
actor GatedTranscriber: Transcribing {
    private let text: String
    private var batches: [[Float]] = []
    private var releasedBatches = 0

    init(text: String = "hello world") {
        self.text = text
    }

    func load() async throws {}

    func transcribe(_ audio: [Float],
                    languages: [String],
                    translatesUnsupported: Bool) async throws -> Transcription {
        batches.append(audio)
        let batch = batches.count
        while releasedBatches < batch {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return Transcription(text: text, language: languages.first)
    }

    /// Let the batch currently being transcribed finish.
    func release() {
        releasedBatches += 1
    }

    func recorded() -> [[Float]] { batches }
    func started() -> Int { batches.count }
}

/// Collects the engine's event stream for assertions.
actor EventCollector {
    var events: [EngineEvent] = []
    func record(_ event: EngineEvent) { events.append(event) }
    func count(of event: EngineEvent) -> Int { events.filter { $0 == event }.count }
}

/// A `DictationEngine` wired to a scripted microphone and the real wake word
/// models, with the event stream captured.
struct EngineHarness {
    let engine: DictationEngine
    let audio: ScriptedAudioSource
    let collector: EventCollector

    func seen() async -> [EngineEvent] { await collector.events }

    func count(of event: EngineEvent) async -> Int { await collector.count(of: event) }

    /// Every transcription the engine emitted, in order.
    func transcriptions() async -> [String] {
        await collector.events.compactMap { event in
            if case .transcription(let text) = event { return text }
            return nil
        }
    }

    func waitFor(_ event: EngineEvent,
                 timeout: Duration = .seconds(10),
                 file: StaticString = #filePath,
                 line: UInt = #line) async throws {
        try await waitFor(event, count: 1, timeout: timeout, file: file, line: line)
    }

    /// Wait until `event` has been seen at least `count` times — how a test
    /// asserts that something happened *again*.
    func waitFor(_ event: EngineEvent,
                 count: Int,
                 timeout: Duration = .seconds(10),
                 file: StaticString = #filePath,
                 line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await collector.count(of: event) >= count { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        let seen = await collector.events
        XCTFail("timed out waiting for \(count)x \(event); saw \(seen)", file: file, line: line)
    }

    func waitForTranscriptions(_ count: Int,
                               timeout: Duration = .seconds(10),
                               file: StaticString = #filePath,
                               line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await transcriptions().count >= count { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        let seen = await collector.events
        XCTFail("timed out waiting for \(count) transcriptions; saw \(seen)", file: file, line: line)
    }

    /// Assert an event stays unseen for a while — the counterpart to `waitFor`.
    ///
    /// `count` is how many occurrences would be too many, so `count: 2` asserts
    /// that something does not happen a *second* time.
    func neverSees(_ event: EngineEvent,
                   count: Int = 1,
                   within: Duration = .milliseconds(500),
                   file: StaticString = #filePath,
                   line: UInt = #line) async throws {
        let deadline = ContinuousClock.now + within
        while ContinuousClock.now < deadline {
            if await collector.count(of: event) >= count {
                XCTFail("unexpected \(count)x \(event)", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

extension XCTestCase {
    /// Build an engine over a scripted microphone.
    ///
    /// - Parameters:
    ///   - transcriber: stands in for Whisper.
    ///   - cancelWord: which word model the engine listens for.
    ///   - languages: what the user selected.
    ///   - primed: whether to feed the moment of audio that makes the engine
    ///     call itself idle. Off for tests about an engine with no microphone
    ///     behind it.
    func makeEngineHarness(transcriber: any Transcribing = StubTranscriber(),
                           cancelWord: HotWord = .defaultWord,
                           languages: [String] = ["en"],
                           primed: Bool = true) async -> EngineHarness {
        let audio = ScriptedAudioSource()
        let engine = DictationEngine(
            capture: audio,
            transcriber: transcriber,
            modelsDirectory: EngineTestModels.directory
        )
        let collector = EventCollector()

        let events = await engine.events()
        Task {
            for await event in events {
                await collector.record(event)
            }
        }

        await engine.start(
            languages: languages,
            cancelWordPath: cancelWord.modelPath(in: EngineTestModels.directory)
        )

        // The loop only reports itself idle once audio is actually arriving.
        if primed {
            audio.sendSilence(seconds: 0.2)
        }

        addTeardownBlock { await engine.stop() }
        return EngineHarness(engine: engine, audio: audio, collector: collector)
    }

    /// Start dictating and wait for the engine to say it is listening.
    func activate(_ harness: EngineHarness) async throws {
        await harness.engine.activate()
        try await harness.waitFor(.ready)
    }
}
