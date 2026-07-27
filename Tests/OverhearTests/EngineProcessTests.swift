import XCTest
@testable import Overhear

@MainActor
final class EngineProcessTests: OverhearTestCase {
    private var engine: EngineProcess?

    override func tearDown() async throws {
        engine?.stop()
        engine = nil
        try await super.tearDownWithError()
    }

    /// A started engine plus the pieces a test needs to drive and observe it.
    private struct Started {
        let process: EngineProcess
        let state: AppState
        let fake: FakeEngine
    }

    private func start(steps: [FakeEngineStep],
                       injector: TextInjecting = SpyInjector()) throws -> Started {
        let fake = try FakeEngine(steps: steps, directory: tempDirectory)
        let state = AppState()
        let process = EngineProcess(appState: state, injector: injector, resolveLaunch: { fake.launch })
        engine = process
        process.start()
        return Started(process: process, state: state, fake: fake)
    }

    // B1 — event to state mapping

    func testEventsMapToStatuses() async throws {
        let cases: [(FakeEngineStep, EngineStatus)] = [
            (.event("idle"), .idle),
            (.event("ready"), .ready),
            (.event("speech_start"), .listening),
            (.event("transcribing"), .transcribing),
            (.event("error", ["message": "boom"]), .error),
        ]

        for (step, expected) in cases {
            let started = try start(steps: [step])
            await waitUntil("status \(expected)") { started.state.status == expected }
            started.process.stop()
        }
    }

    func testErrorEventCarriesItsMessage() async throws {
        let started = try start(steps: [.event("error", ["message": "engine exploded"])])

        await waitUntil("error status") { started.state.status == .error }
        XCTAssertEqual(started.state.errorMessage, "engine exploded")
    }

    func testWarningDoesNotChangeStatus() async throws {
        let started = try start(steps: [
            .event("ready"),
            .wait(0.1),
            .event("warning", ["message": "audio device changed"]),
        ])

        await waitUntil("ready") { started.state.status == .ready }
        await assertNever("status change on warning") { started.state.status != .ready }
    }

    func testCancelEventReturnsToReadyAndFlashes() async throws {
        let started = try start(steps: [
            .event("transcribing"),
            .wait(0.1),
            .event("wake_word_cancel"),
        ])

        await waitUntil("cancel handled") { started.state.showCancelled }
        XCTAssertEqual(started.state.status, .ready)
    }

    // B2 / B4 — transcription handling

    func testTranscriptionIsRecordedAndInjected() async throws {
        let spy = SpyInjector()
        let started = try start(steps: [.event("transcription", ["text": "hello world"])],
                                injector: spy)

        await waitUntil("transcription handled") { !started.state.recentTranscriptions.isEmpty }
        XCTAssertEqual(started.state.recentTranscriptions, ["hello world"])
        XCTAssertEqual(spy.injected, ["hello world"])
    }

    func testEmptyTranscriptionIsIgnored() async throws {
        let spy = SpyInjector()
        let started = try start(steps: [
            .event("transcription", ["text": ""]),
            .wait(0.1),
            .event("ready"),
        ], injector: spy)

        await waitUntil("engine reached ready") { started.state.status == .ready }
        XCTAssertTrue(started.state.recentTranscriptions.isEmpty)
        XCTAssertTrue(spy.injected.isEmpty)
    }

    func testUnicodeTranscriptionSurvivesTheWire() async throws {
        let text = "zażółć gęślą jaźń 🎙"
        let spy = SpyInjector()
        _ = try start(steps: [.event("transcription", ["text": text])], injector: spy)

        await waitUntil("transcription handled") { !spy.injected.isEmpty }
        XCTAssertEqual(spy.injected, [text])
    }

    // B8 / B13 — commands reaching the engine

    func testActivateAndDeactivateAreSent() async throws {
        let started = try start(steps: [.event("idle")])
        await waitUntil("idle") { started.state.status == .idle }

        started.process.activate()
        started.process.deactivate()

        await waitUntil("commands recorded") { started.fake.commandNames.count >= 2 }
        XCTAssertEqual(started.fake.commandNames, ["activate", "deactivate"])
    }

    // B14 — crash handling

    func testUnpromptedExitBecomesAnError() async throws {
        let started = try start(steps: [.event("idle"), .wait(0.1), .exit(3)])

        await waitUntil("error after crash") { started.state.status == .error }
        XCTAssertEqual(started.state.errorMessage, "Engine exited with code 3")
    }

    func testStopDoesNotLookLikeACrash() async throws {
        let started = try start(steps: [.event("idle")])
        await waitUntil("idle") { started.state.status == .idle }

        started.process.stop()

        XCTAssertEqual(started.state.status, .stopped)
        await assertNever("error after an intentional stop", within: 1.0) {
            started.state.status == .error
        }
        XCTAssertNil(started.state.errorMessage)
    }

    // B15 — stdout framing robustness

    func testEventSplitAcrossWritesIsParsed() async throws {
        let started = try start(steps: [
            .raw("{\"event\":\"re"),
            .wait(0.15),
            .raw("ady\"}\n"),
        ])

        await waitUntil("split event parsed") { started.state.status == .ready }
    }

    func testSeveralEventsInOneWriteAreAllParsed() async throws {
        let spy = SpyInjector()
        let started = try start(steps: [
            .raw("{\"event\":\"idle\"}\n{\"event\":\"transcription\",\"text\":\"one\"}\n{\"event\":\"ready\"}\n"),
        ], injector: spy)

        await waitUntil("last event of the batch applied") { started.state.status == .ready }
        XCTAssertEqual(spy.injected, ["one"])
    }

    func testGarbageLinesAreSkippedWithoutKillingTheReader() async throws {
        let started = try start(steps: [
            .raw("not json at all\n"),
            .emit("{\"no_event_key\": true}"),
            .raw("\n"),
            .emit("{\"event\":\"ready\"}"),
        ])

        await waitUntil("reader survived the garbage") { started.state.status == .ready }
    }

    func testVeryLongLineIsParsed() async throws {
        let long = String(repeating: "a", count: 100_000)
        let spy = SpyInjector()
        _ = try start(steps: [.event("transcription", ["text": long])], injector: spy)

        await waitUntil("100KB line parsed") { !spy.injected.isEmpty }
        XCTAssertEqual(spy.injected.first?.count, long.count)
    }

    // B16 — launch failures

    func testEngineNotFoundIsReported() {
        let state = AppState()
        let process = EngineProcess(appState: state, injector: SpyInjector(),
                                    resolveLaunch: { throw EngineLaunchError.engineNotFound })
        process.start()

        XCTAssertEqual(state.status, .error)
        XCTAssertEqual(state.errorMessage, "Could not find dictation_engine.py")
    }

    func testPythonNotFoundIsReported() {
        let state = AppState()
        let process = EngineProcess(appState: state, injector: SpyInjector(),
                                    resolveLaunch: { throw EngineLaunchError.pythonNotFound })
        process.start()

        XCTAssertEqual(state.status, .error)
        XCTAssertEqual(state.errorMessage, "Python 3 not found. Run: brew install python3")
    }

    func testVenvInterpretersOutrankSystemOnes() throws {
        let candidates = EngineProcess.pythonCandidates(
            enginePath: "/opt/app/Engine/dictation_engine.py",
            resourcePath: "/opt/app/Contents/Resources",
            bundlePath: "/Applications/Overhear.app",
            home: URL(fileURLWithPath: "/Users/someone")
        )

        let firstSystem = try XCTUnwrap(
            candidates.firstIndex(where: { EngineProcess.systemPythonCandidates.contains($0) }))
        let lastVenv = try XCTUnwrap(candidates.lastIndex(where: { $0.contains("/.venv/") }))

        XCTAssertLessThan(lastVenv, firstSystem,
                          "a system interpreter would start and then fail on import")
        XCTAssertEqual(candidates.first, "/opt/app/.venv/bin/python3",
                       "the venv beside the engine script should win")
        XCTAssertTrue(candidates.contains(
            "/Users/someone/Library/Application Support/Overhear/.venv/bin/python3"))
    }
}
