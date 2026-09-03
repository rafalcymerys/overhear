import SwiftUI
import XCTest
@testable import Overhear

/// Checking, asking for, and noticing the two permissions dictation needs.
///
/// The window they are granted from is `Specs/Setup.md`, covered in SetupTests
/// — which drives the same `FakeSystem` from here.
@MainActor
final class PermissionsTests: OverhearTestCase {
    nonisolated(unsafe) private var system: FakePermissionSystem!

    override func setUpWithError() throws {
        try super.setUpWithError()
        system = FakePermissionSystem()
    }

    private func makeService() -> PermissionsService {
        PermissionsService(system: system.make())
    }

    // MARK: - What is missing

    func testNothingIsGrantedOnAFreshMac() {
        let service = makeService()

        XCTAssertFalse(service.allGranted)
        XCTAssertEqual(service.missing, [.microphone, .textInsertion])
    }

    func testOneGrantIsNotEnough() {
        system.microphone = .granted
        let service = makeService()

        XCTAssertFalse(service.allGranted)
        XCTAssertEqual(service.missing, [.textInsertion])
    }

    func testBothGrantsClearTheGate() {
        system.microphone = .granted
        system.textInsertion = .granted

        XCTAssertTrue(makeService().allGranted)
        XCTAssertEqual(makeService().missing, [])
    }

    // MARK: - Dialog or System Settings

    func testAnUnansweredPermissionGetsTheSystemDialog() {
        XCTAssertEqual(PermissionsService.request(for: .notDetermined, alreadyPrompted: false), .systemDialog)
    }

    func testASecondAskGoesToSystemSettings() {
        // macOS shows its dialog once per launch; a button that silently does
        // nothing would leave the user stuck.
        XCTAssertEqual(PermissionsService.request(for: .notDetermined, alreadyPrompted: true), .systemSettings)
    }

    func testADeniedPermissionGoesStraightToSystemSettings() {
        XCTAssertEqual(PermissionsService.request(for: .denied, alreadyPrompted: false), .systemSettings)
    }

    // MARK: - Asking

    func testGrantingTheMicrophoneUpdatesTheState() {
        let service = makeService()

        service.request(.microphone)

        XCTAssertEqual(system.dialogs, [.microphone])
        XCTAssertEqual(service.state(of: .microphone), .granted)
    }

    func testDecliningTheMicrophoneSendsTheNextAskToSystemSettings() {
        system.microphoneAnswer = false
        let service = makeService()

        service.request(.microphone)
        XCTAssertEqual(service.state(of: .microphone), .denied)

        service.request(.microphone)
        XCTAssertEqual(system.dialogs, [.microphone])
        XCTAssertEqual(system.openedSettings, [Permission.microphone.settingsURL])
    }

    func testTextInsertionIsPromptedOnceThenPointsAtSystemSettings() {
        let service = makeService()

        service.request(.textInsertion)
        XCTAssertEqual(system.dialogs, [.textInsertion])
        XCTAssertEqual(service.nextRequest(for: .textInsertion), .systemSettings)

        service.request(.textInsertion)
        XCTAssertEqual(system.dialogs, [.textInsertion])
        XCTAssertEqual(system.openedSettings, [Permission.textInsertion.settingsURL])
    }

    func testAskingForAGrantedPermissionDoesNothing() {
        system.microphone = .granted
        let service = makeService()

        service.request(.microphone)

        XCTAssertEqual(system.dialogs, [])
        XCTAssertEqual(system.openedSettings, [])
    }

    // MARK: - Noticing a grant made elsewhere

    func testWatchingPicksUpAGrantMadeInSystemSettings() async {
        let service = makeService()
        service.beginWatching(interval: 0.02)
        defer { service.stopWatching() }

        system.microphone = .granted
        system.textInsertion = .granted

        await waitUntil("the grants to be noticed") { service.allGranted }
    }

    func testStateIsPublishedCompleteRatherThanHalfUpdated() {
        // The launch gate keys off this publisher, so a snapshot with one
        // permission updated and the other stale would start dictation early.
        let service = makeService()
        var snapshots: [[Permission: PermissionState]] = []
        let observation = service.$states.sink { snapshots.append($0) }
        defer { observation.cancel() }

        system.microphone = .granted
        system.textInsertion = .granted
        service.refresh()

        XCTAssertEqual(snapshots.last.map(PermissionsService.allGranted), true)
        XCTAssertFalse(snapshots.dropLast().contains { $0[.microphone] == .granted && $0[.textInsertion] != .granted })
    }
}
