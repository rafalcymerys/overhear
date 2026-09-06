import XCTest
@testable import Overhear

/// `Specs/StatusDisplay.md` — a batch that could not be transcribed.
///
/// The failure the engine survives, which is what separates it from a model
/// that would not load: dictation is still running, so the menu bar has nothing
/// to say and the overlay carries it alone. Until it happens three times in a
/// row, at which point it is the model and not the audio.
@MainActor
final class BatchFailureTests: OverhearTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await EngineTestModels.ensure()
    }

    /// `Specs/StatusDisplay.md` — the engine carries on after one, so the menu
    /// bar has nothing to say. The exclamation means only the user can fix it,
    /// which is untrue of a lost utterance, and a message left in app state
    /// would outlive the batch it describes.
    func testAFailedBatchShowsOnTheOverlayAndLeavesTheMenuBarAlone() async throws {
        let harness = try await makeHarness(transcriber: FailingTranscriber(failures: 1))
        defer { harness.controller.stop() }

        try await harness.dictateOneBatch()

        await waitUntil("the lost utterance is shown") { harness.appState.showFailedBatch }
        XCTAssertNotEqual(harness.appState.status, .error, "the icon says nothing about a lost batch")
        XCTAssertNil(harness.appState.errorMessage, "nothing is left behind for the menu to name")
        XCTAssertTrue(harness.injector.injected.isEmpty, "nothing reaches the document")
        XCTAssertTrue(harness.appState.recentTranscriptions.isEmpty, "nor the menu")
    }

    /// Dictation is still running afterwards, which is the difference between
    /// this failure and the one that loads a model.
    func testDictationCarriesOnAfterAFailedBatch() async throws {
        let harness = try await makeHarness(transcriber: FailingTranscriber(failures: 1))
        defer { harness.controller.stop() }

        try await harness.dictateOneBatch()
        await waitUntil("the lost utterance is shown") { harness.appState.showFailedBatch }

        await waitUntil("dictation is ready again") { harness.appState.status == .ready }
        try await harness.dictateOneBatch()

        await waitUntil("the next utterance arrives") { harness.injector.injected == ["hello world"] }
    }

    /// Three in a row is the model rather than the audio. Carrying on would
    /// flash a failure at the user for as long as they kept speaking without
    /// ever inserting a word, so the engine gives up and says so the way a
    /// model that would not load does.
    func testThreeFailedBatchesInARowStopTheEngine() async throws {
        let harness = try await makeHarness(transcriber: FailingTranscriber())
        defer { harness.controller.stop() }

        for _ in 1...3 {
            try await harness.dictateOneBatch()
        }

        await waitUntil("the engine gives up") { harness.appState.status == .error }
        XCTAssertNotNil(harness.appState.errorMessage, "the menu has something to name")
        XCTAssertEqual(MenuBarAction(needsSetup: false,
                                     status: harness.appState.status,
                                     failure: harness.appState.errorMessage),
                       .failed(reason: harness.appState.errorMessage!),
                       "and offers Try Again rather than Start Listening")
    }

    /// Stopping and starting again is a fresh run. Three bad batches spread
    /// over an afternoon, each dictated separately, are three bad batches — not
    /// a model that has stopped working.
    func testStoppingAndStartingAgainForgetsWhatFailedBefore() async throws {
        let harness = try await makeHarness(transcriber: FailingTranscriber())
        defer { harness.controller.stop() }

        for _ in 1...2 {
            try await harness.dictateOneBatch()
            await waitUntil("the lost utterance is shown") { harness.appState.showFailedBatch }
        }

        harness.controller.deactivate()
        await waitUntil("dictation stops") { !harness.appState.status.isActive }
        harness.controller.activate()
        await waitUntil("dictation is ready again") { harness.appState.status == .ready }

        try await harness.dictateOneBatch()

        XCTAssertNotEqual(harness.appState.status, .error,
                          "a third failure in a new run is not a third in a row")
    }

    /// The count is of failures *in a row*. A single bad batch between good
    /// ones is the pasteboard's bad luck, not a broken model, and dictating all
    /// afternoon should not accumulate its way into a stopped engine.
    func testAnOccasionalFailureNeverStopsTheEngine() async throws {
        let harness = try await makeHarness(transcriber: FailingTranscriber(failures: 1))
        defer { harness.controller.stop() }

        for _ in 1...4 {
            try await harness.dictateOneBatch()
            await waitUntil("dictation is ready again") { harness.appState.status == .ready }
        }

        XCTAssertNotEqual(harness.appState.status, .error)
        XCTAssertEqual(harness.injector.injected.count, 3, "every batch after the first arrived")
    }
}
