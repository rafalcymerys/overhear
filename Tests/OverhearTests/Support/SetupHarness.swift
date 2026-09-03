import Foundation
import XCTest
@testable import Overhear

/// Stands in for TCC: records what was asked for, and lets a test flip an
/// answer the way System Settings would.
///
/// Shared by the permissions suite and the setup suite, which drive the same
/// two grants from either side of the window.
final class FakePermissionSystem: @unchecked Sendable {
    var microphone: PermissionState = .notDetermined
    var textInsertion: PermissionState = .notDetermined
    var microphoneAnswer = true

    private(set) var dialogs: [Permission] = []
    private(set) var openedSettings: [URL] = []

    func make() -> PermissionsService.System {
        PermissionsService.System(
            microphoneState: { [unowned self] in microphone },
            textInsertionState: { [unowned self] in textInsertion },
            askForMicrophone: { [unowned self] completion in
                dialogs.append(.microphone)
                microphone = microphoneAnswer ? .granted : .denied
                completion(microphoneAnswer)
            },
            askForTextInsertion: { [unowned self] in dialogs.append(.textInsertion) },
            openSettings: { [unowned self] url in openedSettings.append(url) }
        )
    }
}

/// A coordinator and everything behind it, so a setup test can reach the disk,
/// the grants and the stored settings that the window reads.
@MainActor
struct SetupHarness {
    let setup: SetupCoordinator
    let models: TranscriptionModelService
    let settings: AppSettings
    let system: FakePermissionSystem

    func grantBothPermissions() {
        system.microphone = .granted
        system.textInsertion = .granted
        setup.permissions.refresh()
    }

    func grant(_ permission: Permission) {
        set(permission, to: .granted)
    }

    /// Switched off in System Settings after setup was finished, which is what
    /// brings the window back.
    func revoke(_ permission: Permission) {
        set(permission, to: .denied)
    }

    private func set(_ permission: Permission, to state: PermissionState) {
        switch permission {
        case .microphone: system.microphone = state
        case .textInsertion: system.textInsertion = state
        }
        setup.permissions.refresh()
    }
}

extension OverhearTestCase {
    /// - Parameter activeModelID: what the last run left active, for the cases
    ///   that come back to setup with a model already chosen.
    @MainActor
    func makeSetup(system: FakePermissionSystem,
                   activeModelID: String? = nil,
                   download: TranscriptionModelService.Downloader? = nil) -> SetupHarness {
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        if let activeModelID {
            settings.activeModelID = activeModelID
        }
        let models = makeModelService(download: download, settings: settings)
        return SetupHarness(
            setup: SetupCoordinator(
                permissions: PermissionsService(system: system.make()),
                models: models,
                settings: settings
            ),
            models: models,
            settings: settings,
            system: system
        )
    }
}
