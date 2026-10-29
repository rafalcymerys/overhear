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

    /// Weak, not unowned: the service can outlive the fake. A test that starts
    /// the poll lets go of the fake when it returns, and the teardown block
    /// that stops the poll runs only after that — a tick in between is a read
    /// from a test that has finished, and has to be harmless.
    func make() -> PermissionsService.System {
        PermissionsService.System(
            microphoneState: { [weak self] in self?.microphone ?? .notDetermined },
            textInsertionState: { [weak self] in self?.textInsertion ?? .notDetermined },
            askForMicrophone: { [weak self] completion in
                guard let self else { return }
                dialogs.append(.microphone)
                microphone = microphoneAnswer ? .granted : .denied
                completion(microphoneAnswer)
            },
            askForTextInsertion: { [weak self] in self?.dialogs.append(.textInsertion) },
            openSettings: { [weak self] url in self?.openedSettings.append(url) }
        )
    }
}

/// Stands in for openWakeWord's release assets: writes a file wherever one is
/// asked for, and can be told to fail or to hold a download open.
final class FakeWakeWordRemote: @unchecked Sendable {
    private(set) var requested: [String] = []
    /// Asset names that throw instead of arriving.
    var failing: Set<String> = []
    /// Set to hold every fetch open, so a test can look at a download in flight.
    var stall = false

    func fetch(_ url: URL) async throws -> URL {
        let name = url.lastPathComponent
        requested.append(name)
        if stall {
            try await Task.sleep(for: .seconds(30))
        }
        if failing.contains(name) {
            throw URLError(.notConnectedToInternet)
        }
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fake-\(UUID().uuidString)")
        try Data("model".utf8).write(to: temporary)
        return temporary
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
    let wakeWords: WakeWordSetup
    let remote: FakeWakeWordRemote
    /// Where the wake word models land, so a test can delete one from under
    /// setup the way a user would.
    let wakeWordDirectory: URL

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
    /// - Parameters:
    ///   - activeModelID: what the last run left active, for the cases that
    ///     come back to setup with a model already chosen.
    ///   - wakeWordFiles: what is on disk before the window opens. The default
    ///     is everything, so a test about the model or the permissions is not
    ///     also a test about a download it never mentions; the wake word suite
    ///     asks for `.none` and watches them arrive.
    @MainActor
    func makeSetup(system: FakePermissionSystem,
                   activeModelID: String? = nil,
                   download: TranscriptionModelService.Downloader? = nil,
                   wakeWordFiles: WakeWordFiles = .present,
                   remote: FakeWakeWordRemote = FakeWakeWordRemote()) -> SetupHarness {
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        if let activeModelID {
            settings.activeModelID = activeModelID
        }
        let models = makeModelService(download: download, settings: settings)

        let directory = tempDirectory.appendingPathComponent("wake-words")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in wakeWordFiles.files {
            try? Data("model".utf8).write(to: directory.appendingPathComponent(file))
        }
        let wakeWords = WakeWordSetup(directory: directory, fetch: { try await remote.fetch($0) })

        return SetupHarness(
            setup: SetupCoordinator(
                permissions: PermissionsService(system: system.make()),
                models: models,
                wakeWords: wakeWords,
                settings: settings
            ),
            models: models,
            settings: settings,
            system: system,
            wakeWords: wakeWords,
            remote: remote,
            wakeWordDirectory: directory
        )
    }
}

/// Which wake word models a test starts with on disk.
@MainActor
enum WakeWordFiles {
    /// A Mac that has run Overhear before.
    case present
    /// A first launch.
    case none
    /// One model deleted from under a finished install.
    case allBut(String)

    var files: [String] {
        switch self {
        case .present: return WakeWordSetup.requiredFiles
        case .none: return []
        case let .allBut(missing): return WakeWordSetup.requiredFiles.filter { $0 != missing }
        }
    }
}
