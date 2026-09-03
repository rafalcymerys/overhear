import Combine
import SwiftUI
import XCTest
@testable import Overhear

/// `Specs/Setup.md`, the model card: what it offers, what it fetches, and what
/// it does when a download is cancelled, fails, or was never needed.
@MainActor
final class SetupModelTests: OverhearTestCase {

    private func makeHarness(activeModelID: String? = nil,
                             download: TranscriptionModelService.Downloader? = nil) -> SetupHarness {
        makeSetup(system: FakePermissionSystem(), activeModelID: activeModelID, download: download)
    }

    // MARK: - Choosing and downloading

    func testTheModelCardOffersWhisperBaseWithoutFetchingIt() async {
        let fetched = TestBox(0)
        let harness = makeHarness(download: { model, base, _ in
            fetched.mutate { $0 += 1 }
            FakeModelDownload.write(model, into: base)
        })

        XCTAssertEqual(harness.setup.chosenModel, ModelCatalog.whisperBase)
        XCTAssertEqual(harness.setup.modelCardTitle, "Choose a model")

        await assertNever("a download nobody asked for") { fetched.value > 0 }
        XCTAssertFalse(harness.models.isDownloaded(ModelCatalog.whisperBase))
    }

    func testDownloadingTheChosenModelMakesItActive() async {
        let harness = makeHarness()

        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperBase)

        XCTAssertTrue(harness.models.isDownloaded(ModelCatalog.whisperBase))
        XCTAssertEqual(harness.settings.activeModelID, ModelCatalog.whisperBase.id)
        XCTAssertTrue(harness.setup.isSatisfied(.model))
        XCTAssertEqual(harness.setup.modelCardTitle, "Whisper Base")
    }

    func testChoosingAnotherModelChangesWhatIsFetched() async {
        let harness = makeHarness()

        harness.setup.chosenModelID = ModelCatalog.whisperSmall.id
        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperSmall)

        XCTAssertTrue(harness.models.isDownloaded(ModelCatalog.whisperSmall))
        XCTAssertFalse(harness.models.isDownloaded(ModelCatalog.whisperBase))
        XCTAssertEqual(harness.settings.activeModelID, ModelCatalog.whisperSmall.id)
    }

    func testAModelAlreadyOnDiskIsActivatedRatherThanFetchedAgain() async {
        let fetched = TestBox(0)
        let harness = makeHarness(download: { model, base, _ in
            fetched.mutate { $0 += 1 }
            FakeModelDownload.write(model, into: base)
        })

        harness.models.startDownload(ModelCatalog.whisperSmall)
        await settle(harness.models, ModelCatalog.whisperSmall)
        XCTAssertEqual(fetched.value, 1)

        harness.setup.chosenModelID = ModelCatalog.whisperSmall.id
        harness.setup.download()

        XCTAssertEqual(fetched.value, 1, "nothing was downloaded a second time")
        XCTAssertEqual(harness.settings.activeModelID, ModelCatalog.whisperSmall.id)
        XCTAssertTrue(harness.setup.isSatisfied(.model))
    }

    func testCancellingLeavesNoModelActiveAndSetupUnfinished() async {
        let harness = makeHarness(download: { _, _, _ in
            try await Task.sleep(for: .seconds(30))
        })
        harness.grantBothPermissions()

        harness.setup.download()
        await waitUntil("the download to start") { harness.models.isDownloading(ModelCatalog.whisperBase) }
        harness.setup.cancelDownload()

        XCTAssertFalse(harness.models.isDownloading(ModelCatalog.whisperBase))
        XCTAssertFalse(harness.models.isDownloaded(ModelCatalog.whisperBase))
        XCTAssertFalse(harness.setup.isSatisfied(.model))
        XCTAssertFalse(harness.setup.isComplete)
        XCTAssertTrue(harness.setup.canChooseModel, "the choice comes back once nothing is running")
    }

    func testTheChoiceIsFixedWhileItsDownloadRuns() async {
        let harness = makeHarness(download: { _, _, _ in
            try await Task.sleep(for: .seconds(30))
        })

        harness.setup.download()
        await waitUntil("the download to start") { harness.models.isDownloading(ModelCatalog.whisperBase) }

        XCTAssertFalse(harness.setup.canChooseModel)
        harness.setup.cancelDownload()
    }

    // MARK: - A download that fails

    func testAFailedDownloadKeepsItsCardOpenAndLetsTheNextOneThrough() async {
        let harness = makeHarness(download: { _, _, _ in
            throw URLError(.notConnectedToInternet)
        })

        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperBase)

        XCTAssertNotNil(harness.setup.failure)
        XCTAssertTrue(harness.setup.isBusy(.model))
        XCTAssertTrue(harness.setup.isExpanded(.model), "the failure stays where it happened")
        XCTAssertEqual(harness.setup.firstNeedingAttention, .permission(.microphone),
                       "the rest of the checklist stays usable")
        XCTAssertTrue(harness.setup.isExpanded(.permission(.microphone)))
    }

    func testChoosingAnotherModelPutsThePickerBack() async {
        let harness = makeHarness(download: { _, _, _ in
            throw URLError(.notConnectedToInternet)
        })

        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperBase)
        XCTAssertFalse(harness.setup.canChooseModel)

        harness.setup.chooseAnotherModel()

        XCTAssertNil(harness.setup.failure)
        XCTAssertTrue(harness.setup.canChooseModel)
        XCTAssertEqual(harness.setup.chosenModel, ModelCatalog.whisperBase,
                       "still selected, so a smaller one can be picked instead")
    }

    // MARK: - Coming back to it later

    func testTheActiveModelGoingMissingIsWhatReopensSetup() async {
        let harness = makeHarness()

        harness.setup.chosenModelID = ModelCatalog.whisperSmall.id
        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperSmall)
        harness.grantBothPermissions()
        XCTAssertTrue(harness.setup.isComplete)

        try? FileManager.default.removeItem(at: harness.models.folder(for: ModelCatalog.whisperSmall))
        harness.setup.refresh()

        XCTAssertFalse(harness.setup.isComplete)
        XCTAssertEqual(harness.setup.firstNeedingAttention, .model)
    }

    func testAModelCardReopenedOffersTheModelThatWentMissing() {
        let harness = makeHarness(activeModelID: ModelCatalog.whisperSmall.id)

        XCTAssertEqual(harness.setup.chosenModel, ModelCatalog.whisperSmall,
                       "not the default — the user chose this one before")
    }

    func testNothingIsFetchedUnaskedWhenTheActiveModelIsGone() async {
        let fetched = TestBox(0)
        let harness = makeHarness(
            activeModelID: ModelCatalog.whisperSmall.id,
            download: { model, base, _ in
                fetched.mutate { $0 += 1 }
                FakeModelDownload.write(model, into: base)
            }
        )

        harness.setup.refresh()

        await assertNever("a download nobody asked for") { fetched.value > 0 }
        XCTAssertFalse(harness.setup.isSatisfied(.model))
    }

    func testAModelOtherThanTheActiveOneGoingMissingIsNotSetupsProblem() async {
        let harness = makeHarness()

        harness.models.startDownload(ModelCatalog.whisperSmall)
        await settle(harness.models, ModelCatalog.whisperSmall)
        harness.setup.download()
        await settle(harness.models, ModelCatalog.whisperBase)
        harness.grantBothPermissions()
        XCTAssertTrue(harness.setup.isComplete)

        try? FileManager.default.removeItem(at: harness.models.folder(for: ModelCatalog.whisperSmall))
        harness.setup.refresh()

        XCTAssertTrue(harness.setup.isComplete, "only the active model is checked")
    }
}
