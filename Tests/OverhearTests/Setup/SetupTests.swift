import Combine
import SwiftUI
import XCTest
@testable import Overhear

/// `Specs/Setup.md` — the one window a new install sees: which of the four
/// requirements are outstanding, which card is open, and when it is done.
///
/// The two download cards have suites of their own: `SetupModelTests` and
/// `SetupWakeWordTests`. Everything here starts with the wake word models
/// already on disk, so the card that settles itself stays out of the way.
@MainActor
final class SetupTests: OverhearTestCase {

    private func makeHarness(download: TranscriptionModelService.Downloader? = nil) -> SetupHarness {
        makeSetup(system: FakePermissionSystem(), download: download)
    }

    // MARK: - What the window opens with

    func testTheRequirementsAreTheTwoDownloadsThenTheTwoPermissions() {
        XCTAssertEqual(SetupRequirement.allCases,
                       [.model, .wakeWords, .permission(.microphone), .permission(.textInsertion)])
    }

    func testAFreshInstallHasEverythingOutstanding() {
        let harness = makeSetup(system: FakePermissionSystem(), wakeWordFiles: .none)

        XCTAssertFalse(harness.setup.isComplete)
        for requirement in SetupRequirement.allCases {
            XCTAssertFalse(harness.setup.isSatisfied(requirement), "\(requirement.id) should be outstanding")
        }
    }

    func testTheModelCardIsTheOpenOneAndTheOthersAreFolded() {
        let harness = makeHarness()

        XCTAssertEqual(harness.setup.firstNeedingAttention, .model)
        XCTAssertTrue(harness.setup.isExpanded(.model))
        XCTAssertFalse(harness.setup.isExpanded(.permission(.microphone)))
        XCTAssertFalse(harness.setup.isExpanded(.permission(.textInsertion)))
    }

    /// The one card that is open without wanting anything: it is downloading,
    /// which is the same reason a running model download stays on screen.
    func testTheWakeWordCardIsOpenAndDownloadingButNotTheOneAsking() async {
        let remote = FakeWakeWordRemote()
        remote.stall = true
        let harness = makeSetup(system: FakePermissionSystem(), wakeWordFiles: .none, remote: remote)

        await waitUntil("the wake word download to start") { harness.wakeWords.isWorking }

        XCTAssertTrue(harness.setup.isExpanded(.wakeWords))
        XCTAssertEqual(harness.setup.firstNeedingAttention, .model,
                       "the card that wants something is still the model's")
    }

    // MARK: - Which card is open

    func testTheOpenCardMovesToWhateverIsLeft() async {
        let harness = makeHarness()

        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperBase)

        XCTAssertFalse(harness.setup.isExpanded(.model), "a finished card folds away")
        XCTAssertEqual(harness.setup.firstNeedingAttention, .permission(.microphone))

        harness.grant(.microphone)

        XCTAssertFalse(harness.setup.isExpanded(.permission(.microphone)))
        XCTAssertTrue(harness.setup.isExpanded(.permission(.textInsertion)))
    }

    func testADownloadInProgressDoesNotHoldUpThePermissionsBeneathIt() async {
        let harness = makeHarness(download: { _, _, _ in
            try await Task.sleep(for: .seconds(30))
        })

        harness.setup.download()
        await waitUntil("the download to start") { harness.models.isDownloading(ModelCatalog.whisperBase) }

        XCTAssertTrue(harness.setup.isExpanded(.model), "its progress stays on screen")
        XCTAssertTrue(harness.setup.isExpanded(.permission(.microphone)), "and the next card opens under it")
        harness.setup.cancelDownload()
    }

    func testACardCanBeOpenedAndShutByHand() {
        let harness = makeHarness()

        harness.setup.toggle(.permission(.textInsertion))
        XCTAssertTrue(harness.setup.isExpanded(.permission(.textInsertion)))

        harness.setup.toggle(.model)
        XCTAssertFalse(harness.setup.isExpanded(.model), "the card harness.setup would have opened can be shut")
        XCTAssertFalse(harness.setup.isSatisfied(.model), "and shutting it settles nothing")
    }

    func testAHandOpenedCardGoesBackToTheWindowOnceItIsSettled() {
        let harness = makeHarness()

        harness.setup.toggle(.permission(.microphone))
        XCTAssertTrue(harness.setup.isExpanded(.permission(.microphone)))

        harness.grant(.microphone)

        XCTAssertFalse(harness.setup.isExpanded(.permission(.microphone)))
    }

    /// There is nothing behind a settled card but the line already on screen,
    /// and opening it would offer a decision that has been made.
    func testASettledCardCannotBeOpened() async {
        let harness = makeHarness()
        harness.grant(.microphone)
        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperBase)

        for requirement in [SetupRequirement.model, .wakeWords, .permission(.microphone)] {
            XCTAssertTrue(harness.setup.isSatisfied(requirement), "\(requirement.id) should be settled")
            harness.setup.toggle(requirement)
            XCTAssertFalse(harness.setup.isExpanded(requirement), "\(requirement.id) opened on a click")
        }

        XCTAssertTrue(harness.setup.isExpanded(.permission(.textInsertion)),
                      "and the one still outstanding is unaffected")
    }

    // MARK: - Finishing

    func testSetupIsCompleteOnlyWhenAllOfThemHold() async {
        let harness = makeHarness()

        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperBase)
        XCTAssertFalse(harness.setup.isComplete, "the model alone is not enough")

        harness.grant(.microphone)
        XCTAssertFalse(harness.setup.isComplete)

        harness.grant(.textInsertion)
        XCTAssertTrue(harness.setup.isComplete)
    }

    func testGrantingBothPermissionsAloneLeavesSetupUnfinished() {
        let harness = makeHarness()

        harness.grantBothPermissions()

        XCTAssertFalse(harness.setup.isComplete, "there is still no model on disk")
        XCTAssertEqual(harness.setup.firstNeedingAttention, .model)
    }

    func testARevokedPermissionReopensSetupWithTheOtherTwoDone() async {
        let harness = makeHarness()

        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperBase)
        harness.grantBothPermissions()
        XCTAssertTrue(harness.setup.isComplete)

        harness.revoke(.textInsertion)

        XCTAssertFalse(harness.setup.isComplete)
        XCTAssertTrue(harness.setup.isSatisfied(.model))
        XCTAssertTrue(harness.setup.isSatisfied(.permission(.microphone)))
        XCTAssertEqual(harness.setup.firstNeedingAttention, .permission(.textInsertion))
        XCTAssertEqual(harness.setup.buttonTitle(for: .textInsertion), "Open System Settings",
                       "macOS will not ask again, so the card sends the user there")
    }

    /// The engine is built by reading `harness.settings.activeModel` back, and the
    /// last thing to complete harness.setup is usually the model, whose activation
    /// writes that setting. `@Published` fires from `willSet`, so a subscriber
    /// woken straight from the assignment reads the model it replaced — which
    /// is not on disk, and fails to load. `AppDelegate` takes completion on
    /// the next turn of the loop for exactly this reason.
    func testCompletionIsUsableOnlyOnceTheSettingHasSettled() async {
        let harness = makeHarness()
        harness.grantBothPermissions()

        let readBack = TestBox<[String]>([])
        let settings = harness.settings
        let straightAway = harness.setup.$isComplete
            .filter { $0 }
            .sink { _ in readBack.mutate { $0.append("immediate:" + settings.activeModelID) } }
        let nextTurn = harness.setup.$isComplete
            .filter { $0 }
            .receive(on: RunLoop.main)
            .sink { _ in readBack.mutate { $0.append("deferred:" + settings.activeModelID) } }
        defer {
            straightAway.cancel()
            nextTurn.cancel()
        }

        harness.setup.chosenModelID = ModelCatalog.whisperSmall.id
        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperSmall)
        await waitUntil("the deferred read") { readBack.value.contains { $0.hasPrefix("deferred:") } }

        XCTAssertTrue(readBack.value.contains("immediate:" + ModelCatalog.whisperBase.id),
                      "read from the assignment itself, the setting is still the old model")
        XCTAssertTrue(readBack.value.contains("deferred:" + ModelCatalog.whisperSmall.id),
                      "read a turn later, it is the model that completed harness.setup")
    }

    // MARK: - Layout

    func testTheWindowIsSizedFromTheContentSoNothingIsClipped() {
        // The window takes its height from `fittingSize`; an explanation that
        // wraps to another line has to push that number up rather than get cut
        // off.
        let harness = makeHarness()
        let hosting = NSHostingView(rootView: SetupView(
            setup: harness.setup,
            permissions: harness.setup.permissions,
            models: harness.models,
            wakeWords: harness.wakeWords,
            onQuit: {}
        ))
        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual(hosting.fittingSize.width, 460)
        XCTAssertGreaterThan(hosting.fittingSize.height, 260)
        XCTAssertLessThan(hosting.fittingSize.height, 700)
    }
}

// MARK: - Giving up on the models on disk

/// `Specs/StatusDisplay.md` — **Re-download Models**, the way out of a failure
/// **Try Again** cannot fix.
///
/// Setup counts a file it can see as settled, so a model that is on disk and
/// will not load is invisible to it and survives any number of reopenings.
/// Deleting is what turns that into a problem setup already knows how to solve.
@MainActor
final class SetupDiscardTests: OverhearTestCase {

    func testDiscardingTakesBothDownloadsAndReopensSetup() async {
        let harness = makeSetup(system: FakePermissionSystem())
        harness.grantBothPermissions()
        harness.setup.download()
        await settle(harness.models, harness.settings.activeModel)
        await waitUntil("setup finishes") { harness.setup.isComplete }

        harness.setup.discardModels()

        XCTAssertFalse(harness.models.isDownloaded(harness.settings.activeModel),
                       "the model the engine could not read is gone")
        XCTAssertFalse(harness.setup.isComplete, "so the window has something to do again")
        XCTAssertFalse(harness.setup.isSatisfied(.model))
    }

    /// The active model goes too. `remove(_:)` refuses it, because something has
    /// to transcribe — but that is the very model the engine choked on, and
    /// leaving it is leaving the whole problem.
    func testDiscardingTakesTheActiveModelThatRemoveWouldRefuse() async {
        let harness = makeSetup(system: FakePermissionSystem())
        harness.setup.download()
        await settle(harness.models, harness.settings.activeModel)
        let active = harness.settings.activeModel

        XCTAssertFalse(harness.models.remove(active), "removing the active model is refused")

        harness.setup.discardModels()
        XCTAssertFalse(harness.models.isDownloaded(active))
    }

    /// The card preselects what was active, the same as any other launch that
    /// finds its weights gone — `Specs/Setup.md`.
    func testTheModelThatWasActiveIsStillTheOneOffered() async {
        let harness = makeSetup(system: FakePermissionSystem(), activeModelID: ModelCatalog.whisperSmall.id)
        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperSmall)

        harness.setup.discardModels()

        XCTAssertEqual(harness.settings.activeModelID, ModelCatalog.whisperSmall.id)
        XCTAssertEqual(harness.setup.chosenModelID, ModelCatalog.whisperSmall.id)
    }

    /// A custom word lives in the same directory and is not setup's to delete.
    /// Nothing here has any reason to think it is what the engine choked on.
    func testACustomHotWordSurvives() {
        let harness = makeSetup(system: FakePermissionSystem())
        let custom = harness.wakeWordDirectory.appendingPathComponent("my_word.onnx")
        try? Data("model".utf8).write(to: custom)

        harness.setup.discardModels()

        XCTAssertTrue(FileManager.default.fileExists(atPath: custom.path))
        for file in WakeWordSetup.requiredFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: harness.wakeWordDirectory.appendingPathComponent(file).path),
                "\(file) should have gone"
            )
        }
    }

    /// The hot word card comes up already downloading, so they are on their way
    /// back before the window is even looked at — `Specs/Setup.md`.
    func testTheHotWordModelsStartComingBackOnTheirOwn() async {
        let harness = makeSetup(system: FakePermissionSystem())

        harness.setup.discardModels()

        await waitUntil("the fetch starts again") { !harness.remote.requested.isEmpty }
    }
}
