import Combine
import SwiftUI
import XCTest
@testable import Overhear

/// `Specs/Setup.md` — the one window a new install sees: which of the three
/// requirements are outstanding, which card is open, and when it is done.
///
/// The model card's own behaviour is `SetupModelTests`.
@MainActor
final class SetupTests: OverhearTestCase {

    private func makeHarness(download: TranscriptionModelService.Downloader? = nil) -> SetupHarness {
        makeSetup(system: FakePermissionSystem(), download: download)
    }

    // MARK: - What the window opens with

    func testTheThreeRequirementsAreModelFirstThenTheTwoPermissions() {
        XCTAssertEqual(SetupRequirement.allCases,
                       [.model, .permission(.microphone), .permission(.textInsertion)])
    }

    func testAFreshInstallHasEverythingOutstanding() {
        let harness = makeHarness()

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

    // MARK: - Finishing

    func testSetupIsCompleteOnlyWhenAllThreeHold() async {
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
            onQuit: {}
        ))
        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual(hosting.fittingSize.width, 460)
        XCTAssertGreaterThan(hosting.fittingSize.height, 260)
        XCTAssertLessThan(hosting.fittingSize.height, 700)
    }
}
