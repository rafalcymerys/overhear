import Combine
import XCTest
@testable import Overhear

/// `Specs/Setup.md`, the hot word card: the one requirement that settles
/// itself. It starts downloading as it appears, draws its own progress, and
/// keeps its failure on the card rather than in the menu bar.
@MainActor
final class SetupWakeWordTests: OverhearTestCase {

    private func makeHarness(files: WakeWordFiles = .none,
                             remote: FakeWakeWordRemote = FakeWakeWordRemote()) -> SetupHarness {
        makeSetup(system: FakePermissionSystem(), wakeWordFiles: files, remote: remote)
    }

    private func onDisk(_ harness: SetupHarness) -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: harness.wakeWordDirectory.path)) ?? []
        return Set(files)
    }

    // MARK: - Downloading without being asked

    func testTheCardFetchesTheModelsWithoutBeingTold() async {
        let harness = makeHarness()

        XCTAssertFalse(harness.setup.isSatisfied(.wakeWords))
        await waitUntil("the models to arrive") { harness.setup.isSatisfied(.wakeWords) }

        XCTAssertEqual(onDisk(harness), Set(WakeWordSetup.requiredFiles))
        XCTAssertEqual(Set(harness.remote.requested), Set(WakeWordSetup.modelAssets.values),
                       "fetched under the release's versioned names")
    }

    /// The card is the first thing to fill its bar and the last thing to say
    /// anything, so it has to have a fraction rather than only a sentence.
    func testProgressIsAFractionOfTheFilesThisRunHasToFetch() async {
        let harness = makeHarness()

        // Subscribed rather than polled: a fake download outruns any interval
        // a test could sample at, and every value the bar would have drawn
        // matters here.
        let seen = TestBox<[Double]>([])
        let observation = harness.wakeWords.$progress
            .compactMap { $0 }
            .sink { fraction in seen.mutate { $0.append(fraction) } }
        defer { observation.cancel() }

        await waitUntil("the download to finish") { harness.setup.isSatisfied(.wakeWords) }

        let fractions = seen.value
        XCTAssertEqual(fractions.count, WakeWordSetup.requiredFiles.count + 1,
                       "the bar starts empty and moves once per file")
        XCTAssertEqual(fractions.first, 0)
        XCTAssertEqual(fractions.last, 1)
        XCTAssertEqual(fractions, fractions.sorted(), "it only ever goes forwards")
        XCTAssertNil(harness.setup.wakeWordProgress, "and nothing is left drawing once it is done")
    }

    /// A run fetching one file fills the bar with that file, rather than
    /// showing a sixth of a job it is not doing.
    func testProgressCoversOnlyWhatThisRunFetches() async {
        let harness = makeHarness(files: .allBut("alexa.onnx"))

        let seen = TestBox<[Double]>([])
        let observation = harness.wakeWords.$progress
            .compactMap { $0 }
            .sink { fraction in seen.mutate { $0.append(fraction) } }
        defer { observation.cancel() }

        await waitUntil("the missing model to arrive") { harness.setup.isSatisfied(.wakeWords) }

        XCTAssertEqual(seen.value, [0, 1])
    }

    /// Every launch after the first fetches what is missing and nothing else,
    /// which is usually nothing at all.
    func testOnlyTheMissingModelsAreFetched() async {
        let harness = makeHarness(files: .allBut("hey_jarvis.onnx"))

        await waitUntil("the missing model to arrive") { harness.setup.isSatisfied(.wakeWords) }

        XCTAssertEqual(harness.remote.requested, ["hey_jarvis_v0.1.onnx"])
        XCTAssertEqual(onDisk(harness), Set(WakeWordSetup.requiredFiles))
    }

    func testNothingIsFetchedWhenEveryModelIsAlreadyThere() async {
        let harness = makeHarness(files: .present)

        XCTAssertTrue(harness.setup.isSatisfied(.wakeWords))
        await assertNever("a download nobody needed") { !harness.remote.requested.isEmpty }
    }

    // MARK: - Alongside the rest of setup

    func testThePermissionsCanBeGrantedWhileTheModelsArrive() async {
        let remote = FakeWakeWordRemote()
        remote.stall = true
        let harness = makeHarness(remote: remote)

        await waitUntil("the download to start") { harness.wakeWords.isWorking }

        XCTAssertTrue(harness.setup.isExpanded(.wakeWords), "its progress stays on screen")
        XCTAssertEqual(harness.setup.firstNeedingAttention, .model,
                       "and the card asking for something is not this one")

        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperBase)

        XCTAssertEqual(harness.setup.firstNeedingAttention, .permission(.microphone),
                       "the permissions come up under a download still running")
        harness.grantBothPermissions()
        XCTAssertFalse(harness.setup.isComplete, "but setup is not finished until the models land")
    }

    /// The window closes on whichever requirement settles last, and these are
    /// slow enough that it is often this one.
    func testSetupIsUnfinishedUntilTheModelsLand() async {
        let harness = makeHarness()
        harness.grantBothPermissions()
        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperBase)

        await waitUntil("setup to finish") { harness.setup.isComplete }

        XCTAssertTrue(harness.setup.isSatisfied(.wakeWords))
        XCTAssertFalse(harness.setup.isExpanded(.wakeWords), "a finished card folds away")
    }

    /// A model deleted between launches is setup's business now, so the window
    /// comes back for it rather than the engine failing on it.
    func testAModelDeletedBetweenLaunchesReopensSetup() async {
        let harness = makeHarness(files: .present)
        harness.grantBothPermissions()
        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperBase)
        XCTAssertTrue(harness.setup.isComplete)

        try? FileManager.default.removeItem(at: harness.wakeWordDirectory.appendingPathComponent("alexa.onnx"))
        harness.setup.refresh()

        XCTAssertFalse(harness.setup.isComplete)
        await waitUntil("the deleted model to be fetched back") { harness.setup.isComplete }
        XCTAssertEqual(harness.remote.requested, ["alexa_v0.1.onnx"])
    }

    // MARK: - Failing

    func testAFailureStaysOnTheCardWithARetry() async {
        let remote = FakeWakeWordRemote()
        remote.failing = ["embedding_model.onnx"]
        let harness = makeHarness(remote: remote)

        await waitUntil("the download to fail") { harness.setup.wakeWordFailure != nil }

        XCTAssertTrue(harness.setup.wakeWordFailure?.contains("embedding_model.onnx") == true,
                      "the card names the file it could not fetch")
        XCTAssertFalse(harness.setup.isSatisfied(.wakeWords))
        XCTAssertTrue(harness.setup.isExpanded(.wakeWords))
        XCTAssertEqual(harness.setup.firstNeedingAttention, .model,
                       "a card that failed is outlined rather than holding the queue, as the model's is")
        XCTAssertFalse(onDisk(harness).contains("embedding_model.onnx"), "and nothing partial is left behind")

        remote.failing = []
        harness.setup.retryWakeWords()
        await waitUntil("the retry to finish") { harness.setup.isSatisfied(.wakeWords) }
        XCTAssertNil(harness.setup.wakeWordFailure)
    }

    /// Retrying is the user's decision. Reopening the window or the menu bar
    /// menu refreshes setup, and that must not quietly start it over.
    func testARefreshDoesNotRestartAFailedDownload() async {
        let remote = FakeWakeWordRemote()
        remote.failing = WakeWordSetup.modelAssets.values.reduce(into: Set()) { $0.insert($1) }
        let harness = makeHarness(remote: remote)

        await waitUntil("the download to fail") { harness.setup.wakeWordFailure != nil }
        let attempts = harness.remote.requested.count

        harness.setup.refresh()
        await assertNever("a retry nobody asked for") { harness.remote.requested.count > attempts }
        XCTAssertNotNil(harness.setup.wakeWordFailure, "the failure is still on the card")
    }

    /// It picks up where it stopped: the files that did arrive before the
    /// failure are not fetched twice.
    func testARetryResumesFromTheFilesStillMissing() async {
        let remote = FakeWakeWordRemote()
        remote.failing = ["hey_rhasspy_v0.1.onnx"]
        let harness = makeHarness(remote: remote)

        await waitUntil("the download to fail") { harness.setup.wakeWordFailure != nil }
        let landed = onDisk(harness)
        XCTAssertFalse(landed.isEmpty, "the files before the failing one arrived")

        remote.failing = []
        harness.setup.retryWakeWords()
        await waitUntil("the retry to finish") { harness.setup.isSatisfied(.wakeWords) }

        let refetched = harness.remote.requested.filter { asset in
            landed.contains { WakeWordSetup.modelAssets[$0] == asset }
        }
        XCTAssertEqual(refetched.count, landed.count,
                       "each file that had already landed was requested once, on the first run")
    }
}
