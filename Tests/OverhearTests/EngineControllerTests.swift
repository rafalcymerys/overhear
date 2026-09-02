import Combine
import XCTest
@testable import Overhear

/// The last wiring layer: engine events reaching `AppState`, the overlay and
/// the pasteboard. Everything the menu bar and the overlay render is driven
/// from here, so a mismapped event is a visibly wrong app.
@MainActor
final class EngineControllerTests: OverhearTestCase {
    private static var modelsDirectory: URL { EngineTestModels.directory }

    override func setUp() async throws {
        try await super.setUp()
        try await EngineTestModels.ensure()
    }

    func testDrivesStateThroughADictationAndPastesTheResult() async throws {
        let appState = AppState()
        let injector = SpyInjector()
        let audio = ScriptedAudioSource()

        let controller = EngineController(
            appState: appState,
            injector: injector,
            modelsDirectory: Self.modelsDirectory,
            makeTranscriber: { _ in StubTranscriber() },
            makeAudioSource: { audio }
        )
        defer { controller.stop() }

        controller.start()
        XCTAssertEqual(appState.status, .loading)

        audio.sendSilence(seconds: 0.2)
        await waitUntil("engine reaches idle") { appState.status == .idle }

        controller.activate()
        await waitUntil("engine is ready") { appState.status == .ready }

        audio.sendSpeech(seconds: 1.0)
        await waitUntil("speech is noticed") { appState.status == .listening }

        audio.sendSilence(seconds: 2.0)
        await waitUntil("text is pasted") { injector.injected == ["hello world"] }
        XCTAssertEqual(appState.recentTranscriptions, ["hello world"], "it should also reach the menu")
    }

    /// The menu bar icon and the overlay are drawn from `status` alone, so the
    /// whole cycle has to be published — a missed `transcribing` is a spinner
    /// the user never sees.
    func testEveryStateInTheCycleIsPublished() async throws {
        let log = StatusLog()
        let harness = try await makeHarness(transcribing: "hello world")
        defer { harness.controller.stop() }

        let subscription = harness.appState.$status.sink { log.record($0) }
        defer { subscription.cancel() }

        try await harness.dictateOneBatch()
        await waitUntil("text is pasted") { !harness.injector.injected.isEmpty }

        XCTAssertTrue(log.recorded.follows([.ready, .listening, .transcribing, .ready]),
                      "expected the dictation cycle, saw \(log.recorded)")
    }

    /// A failure to load has to surface — a menu bar app that silently does
    /// nothing is indistinguishable from one that is working.
    func testReportsAMissingModel() async throws {
        let appState = AppState()
        let controller = EngineController(
            appState: appState,
            injector: SpyInjector(),
            modelsDirectory: tempDirectory,
            makeTranscriber: { _ in StubTranscriber() },
            makeAudioSource: { ScriptedAudioSource() }
        )
        defer { controller.stop() }

        controller.start()

        await waitUntil("the failure is reported") { appState.status == .error }
        XCTAssertNotNil(appState.errorMessage)
    }

    func testStopReturnsToStopped() async throws {
        let appState = AppState()
        let audio = ScriptedAudioSource()
        let controller = EngineController(
            appState: appState,
            injector: SpyInjector(),
            modelsDirectory: Self.modelsDirectory,
            makeTranscriber: { _ in StubTranscriber() },
            makeAudioSource: { audio }
        )

        controller.start()
        audio.sendSilence(seconds: 0.2)
        await waitUntil("engine reaches idle") { appState.status == .idle }

        controller.stop()
        XCTAssertEqual(appState.status, .stopped)
        XCTAssertNil(appState.errorMessage)
    }

    /// Dictation stopped and started again keeps what was already transcribed:
    /// the menu is a session-long list, not a per-utterance one.
    func testEarlierTranscriptionsSurviveStoppingAndStartingAgain() async throws {
        let harness = try await makeHarness(transcribing: "hello world")
        defer { harness.controller.stop() }

        try await harness.dictateOneBatch()
        await waitUntil("the first utterance is pasted") { harness.injector.injected.count == 1 }

        harness.controller.deactivate()
        await waitUntil("dictation stops") { !harness.appState.status.isActive }

        harness.controller.activate()
        await waitUntil("dictation is ready again") { harness.appState.status == .ready }
        try await harness.dictateOneBatch()

        await waitUntil("the second utterance is pasted") { harness.injector.injected.count == 2 }
        XCTAssertEqual(harness.appState.recentTranscriptions, ["hello world", "hello world"],
                       "the earlier transcription is still listed")
    }

    // MARK: - The cancel word, as the user sees it

    /// Cancelling has to be visible — the shaking red bars in the menu bar and
    /// the overlay are `showCancelled` — and nothing may reach the document.
    func testCancellingShowsTheCancelledStateAndPastesNothing() async throws {
        let harness = try await makeHarness(transcribing: "hello world")
        defer { harness.controller.stop() }

        harness.audio.sendSpeech(seconds: 0.5)
        harness.audio.send(samples: try SyntheticSample.alexa.load())

        await waitUntil("the cancelled state is shown") { harness.appState.showCancelled }
        XCTAssertEqual(harness.appState.status, .ready, "dictation carries on after a cancel")
        XCTAssertTrue(harness.injector.injected.isEmpty, "nothing is pasted")
        XCTAssertTrue(harness.appState.recentTranscriptions.isEmpty, "nothing reaches the menu")
    }

    // MARK: - Settings that apply without a reload

    /// Turning translation on reaches the running engine: the next batch is
    /// decoded with it, and the audio source is never torn down.
    func testTranslationAppliesToTheNextBatchWithoutAReload() async throws {
        let transcriber = StubTranscriber()
        let harness = try await makeHarness(transcriber: transcriber)
        defer { harness.controller.stop() }

        try await harness.dictateOneBatch()
        await waitUntil("the first utterance is pasted") { harness.injector.injected.count == 1 }

        harness.settings.translateUnsupported = true
        try await harness.dictateOneBatch()
        await waitUntil("the second utterance is pasted") { harness.injector.injected.count == 2 }

        let requests = await transcriber.recordedRequests()
        XCTAssertEqual(requests.map(\.translatesUnsupported), [false, true],
                       "the setting applies to the next batch")
        XCTAssertFalse(harness.audio.isStopped, "toggling it must not rebuild the engine")
        XCTAssertTrue(harness.appState.status.isActive, "dictation stays active")
    }

    /// The same for annotation stripping, which is read per transcription
    /// rather than baked into the engine.
    func testAnnotationStrippingCanBeTurnedOffMidSession() async throws {
        let harness = try await makeHarness(transcribing: "(coughing) hello world")
        defer { harness.controller.stop() }

        try await harness.dictateOneBatch()
        await waitUntil("the annotation is stripped") { harness.injector.injected == ["hello world"] }

        harness.settings.stripAnnotations = false
        try await harness.dictateOneBatch()

        await waitUntil("the annotation is kept") {
            harness.injector.injected == ["hello world", "(coughing) hello world"]
        }
        XCTAssertFalse(harness.audio.isStopped, "toggling it must not rebuild the engine")
    }

    /// The languages reach the engine in a stable order. They are held as a
    /// `Set`, whose iteration order changes between launches, and the decode
    /// falls back to the first one when detection cannot run — an unsorted
    /// hand-over makes that fallback a different language each time.
    func testTheSelectedLanguagesReachTheTranscriberSorted() async throws {
        let transcriber = StubTranscriber()
        let harness = try await makeHarness(transcriber: transcriber) {
            $0.selectedLanguageCodes = ["pl", "en", "de"]
        }
        defer { harness.controller.stop() }

        try await harness.dictateOneBatch()
        await waitUntil("the batch is transcribed") { !harness.injector.injected.isEmpty }

        let requests = await transcriber.recordedRequests()
        XCTAssertEqual(requests.first?.languages, ["de", "en", "pl"])
    }

    // MARK: - R-97

    /// The bug as reported: with nobody speaking, Whisper described the sound it
    /// heard and the description was pasted into the user's document.
    func testAnnotationOnlyTranscriptionsAreNotPasted() async throws {
        for annotation in ["[ Pause ]", "(coughing) (coughing)", "[BLANK_AUDIO]"] {
            let harness = try await makeHarness(transcribing: annotation)
            defer { harness.controller.stop() }

            try await harness.dictateOneBatch()

            XCTAssertTrue(harness.injector.injected.isEmpty, "\(annotation) should not reach the document")
            XCTAssertTrue(harness.appState.recentTranscriptions.isEmpty, "\(annotation) should not reach the menu")
        }
    }

    /// Speech alongside an annotation keeps the speech.
    func testAnnotationsAreStrippedFromRealSpeech() async throws {
        let harness = try await makeHarness(transcribing: "(coughing) hello world")
        defer { harness.controller.stop() }

        try await harness.dictateOneBatch()
        await waitUntil("text is pasted") { harness.injector.injected == ["hello world"] }
    }

    /// With the setting off a parenthesised annotation counts as speech — that
    /// is what the toggle is for. Brackets are stripped either way.
    func testParenthesesSurviveWhenStrippingIsOff() async throws {
        let harness = try await makeHarness(transcribing: "(coughing) hello world") { $0.stripAnnotations = false }
        defer { harness.controller.stop() }

        try await harness.dictateOneBatch()
        await waitUntil("text is pasted") { harness.injector.injected == ["(coughing) hello world"] }
    }

    /// Room noise is loud enough to be recorded as a batch — the level
    /// threshold does not catch it — so what keeps it out of the document is
    /// what Whisper makes of it, and the filter on the way past.
    func testNoiseWithNoSpeechInItNeverReachesTheDocument() async throws {
        let harness = try await makeHarness(transcribing: "[BLANK_AUDIO]")
        defer { harness.controller.stop() }

        await harness.audio.sendPaced(samples: try SyntheticSample.backgroundNoise.load())
        harness.audio.sendSilence(seconds: 2.0)
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertTrue(harness.injector.injected.isEmpty, "noise is not dictation")
        XCTAssertTrue(harness.appState.recentTranscriptions.isEmpty)
        XCTAssertTrue(harness.appState.status.isActive, "dictation stays active")
    }

    // MARK: - Changing the model

    /// Activating a model has to load different weights, which is a new
    /// transcriber. Restarting for anything else — a language, the cancel word
    /// — must not be, or every toggle would cost a model load.
    func testANewTranscriberIsBuiltOnlyWhenTheModelChanges() async throws {
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        let requested = TestBox<[String]>([])
        let audio = ScriptedAudioSource()
        let controller = EngineController(
            appState: AppState(),
            injector: SpyInjector(),
            modelsDirectory: Self.modelsDirectory,
            makeTranscriber: { model in
                requested.mutate { $0.append(model.id) }
                return StubTranscriber()
            },
            makeAudioSource: { audio },
            settings: settings
        )
        defer { controller.stop() }

        controller.start()
        XCTAssertEqual(requested.value, [ModelCatalog.whisperBase.id])

        // A restart with the same model reuses the loaded one.
        controller.stop()
        controller.start()
        XCTAssertEqual(requested.value, [ModelCatalog.whisperBase.id],
                       "restarting must not reload the same weights")

        settings.activeModelID = ModelCatalog.whisperSmall.id
        controller.stop()
        controller.start()
        XCTAssertEqual(requested.value, [ModelCatalog.whisperBase.id, ModelCatalog.whisperSmall.id])
    }

    /// The engine is given the languages the active model can actually
    /// transcribe. Handing it Polish with an English-only model loaded is how
    /// Polish comes back as English.
    func testAnEnglishOnlyModelIsOnlyEverGivenEnglish() async throws {
        let transcriber = StubTranscriber()
        let harness = try await makeHarness(transcriber: transcriber) {
            $0.selectedLanguageCodes = ["en", "pl"]
            $0.activeModelID = ModelCatalog.whisperBaseEnglish.id
        }
        defer { harness.controller.stop() }

        try await harness.dictateOneBatch()
        await waitUntil("the batch is transcribed") { !harness.injector.injected.isEmpty }

        let requests = await transcriber.recordedRequests()
        XCTAssertEqual(requests.first?.languages, ["en"])
    }

    // MARK: - Harness

    private struct Harness {
        let controller: EngineController
        let appState: AppState
        let injector: SpyInjector
        let audio: ScriptedAudioSource
        let settings: AppSettings

        /// Speak, pause, and let the batch run through transcription.
        func dictateOneBatch() async throws {
            audio.sendSpeech(seconds: 1.0)
            audio.sendSilence(seconds: 2.0)
            try await Task.sleep(for: .milliseconds(400))
        }
    }

    private func makeHarness(transcribing text: String,
                             configure: (AppSettings) -> Void = { _ in }) async throws -> Harness {
        try await makeHarness(transcriber: StubTranscriber(text: text), configure: configure)
    }

    private func makeHarness(transcriber: any Transcribing,
                             configure: (AppSettings) -> Void = { _ in }) async throws -> Harness {
        let appState = AppState()
        let injector = SpyInjector()
        let audio = ScriptedAudioSource()
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        configure(settings)

        let controller = EngineController(
            appState: appState,
            injector: injector,
            modelsDirectory: Self.modelsDirectory,
            makeTranscriber: { _ in transcriber },
            makeAudioSource: { audio },
            settings: settings
        )

        controller.start()
        audio.sendSilence(seconds: 0.2)
        await waitUntil("engine reaches idle") { appState.status == .idle }
        controller.activate()
        await waitUntil("engine is ready") { appState.status == .ready }

        return Harness(controller: controller,
                       appState: appState,
                       injector: injector,
                       audio: audio,
                       settings: settings)
    }
}

/// Every status the app published, in order.
///
/// Polling `appState.status` sees only where it happens to land; the states the
/// icon renders pass through in milliseconds.
private final class StatusLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [EngineStatus] = []

    func record(_ status: EngineStatus) {
        lock.withLock { values.append(status) }
    }

    var recorded: [EngineStatus] {
        lock.withLock { values }
    }
}

private extension Array where Element == EngineStatus {
    /// Whether these statuses appear in order, with anything in between.
    func follows(_ expected: [EngineStatus]) -> Bool {
        var remaining = expected[...]
        for status in self where status == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }
}
