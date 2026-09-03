import AVFoundation
import AppKit
import ApplicationServices

/// A permission the app cannot dictate without.
enum Permission: String, CaseIterable, Identifiable {
    /// Hearing the user — the engine captures audio through the microphone.
    case microphone
    /// Typing for the user — the paste that delivers a transcription is a
    /// synthetic Cmd+V, which macOS gates behind Accessibility.
    case textInsertion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .textInsertion: return "Inserting text in your apps"
        }
    }

    var explanation: String {
        switch self {
        case .microphone:
            return "Overhear listens through your microphone to hear what you dictate. Audio never leaves your Mac."
        case .textInsertion:
            return "Transcriptions are pasted into whatever app you're using. For this, Overhear needs the accessibility permission."
        }
    }

    var buttonTitle: String {
        switch self {
        case .microphone: return "Grant Microphone Permission"
        case .textInsertion: return "Grant Permission for Inserting Text"
        }
    }

    /// The System Settings pane holding the switch, for when macOS won't show
    /// its own dialog any more.
    var settingsURL: URL {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .textInsertion:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        }
    }
}

enum PermissionState: Equatable {
    /// Never answered — macOS will still show its dialog.
    case notDetermined
    /// Answered with a no. The dialog is spent; only System Settings can undo it.
    case denied
    case granted
}

/// What asking for a permission should actually do.
enum PermissionRequest: Equatable {
    case systemDialog
    case systemSettings
}

/// Tracks the two permissions Overhear needs and asks for them.
///
/// Neither grant arrives as a notification — Accessibility is switched on in
/// System Settings with the app none the wiser, and the microphone switch is
/// just as silent — so the state is polled while the permissions window is up.
@MainActor
final class PermissionsService: ObservableObject {
    /// The system calls behind each permission. Injected so tests can drive the
    /// flow without TCC dialogs.
    struct System {
        var microphoneState: () -> PermissionState = {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        }

        /// `AXIsProcessTrusted` can't tell "never asked" from "said no", so an
        /// untrusted process reads as undetermined and gets one shot at the
        /// dialog; `prompted` covers the difference from there.
        var textInsertionState: () -> PermissionState = {
            AXIsProcessTrusted() ? .granted : .notDetermined
        }

        var askForMicrophone: (@escaping (Bool) -> Void) -> Void = { completion in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }

        var askForTextInsertion: () -> Void = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        var openSettings: (URL) -> Void = { _ = NSWorkspace.shared.open($0) }
    }

    @Published private(set) var states: [Permission: PermissionState] = [:]
    /// Permissions whose system dialog has already been shown this launch.
    @Published private(set) var prompted: Set<Permission> = []

    private let system: System
    private var pollTimer: Timer?
    /// Asks macOS is still showing a dialog for. Clicking the button again
    /// while the user is looking at that dialog should do nothing.
    private var asking: Set<Permission> = []

    init(system: System = System()) {
        self.system = system
        refresh()
    }

    deinit {
        pollTimer?.invalidate()
    }

    var allGranted: Bool {
        Self.allGranted(states)
    }

    var missing: [Permission] {
        Permission.allCases.filter { state(of: $0) != .granted }
    }

    func state(of permission: Permission) -> PermissionState {
        states[permission] ?? .notDetermined
    }

    /// One assignment rather than one per permission, so observers never see a
    /// half-updated picture.
    func refresh() {
        states = [
            .microphone: system.microphoneState(),
            .textInsertion: system.textInsertionState(),
        ]
    }

    static func allGranted(_ states: [Permission: PermissionState]) -> Bool {
        Permission.allCases.allSatisfy { states[$0] == .granted }
    }

    /// macOS shows its dialog only while the answer is still open, and only
    /// once per launch. After that the switch in System Settings is the only
    /// way through, so send the user there rather than to a button that would
    /// silently do nothing.
    static func request(for state: PermissionState, alreadyPrompted: Bool) -> PermissionRequest {
        state == .notDetermined && !alreadyPrompted ? .systemDialog : .systemSettings
    }

    func nextRequest(for permission: Permission) -> PermissionRequest {
        Self.request(for: state(of: permission), alreadyPrompted: prompted.contains(permission))
    }

    func request(_ permission: Permission) {
        guard state(of: permission) != .granted, !asking.contains(permission) else { return }

        switch nextRequest(for: permission) {
        case .systemDialog:
            switch permission {
            case .microphone:
                // Count the dialog as spent only once macOS reports the answer,
                // so the button doesn't turn into "Open System Settings" while
                // the user is still reading the dialog.
                asking.insert(permission)
                system.askForMicrophone { [weak self] _ in
                    guard let self else { return }
                    self.asking.remove(permission)
                    self.prompted.insert(permission)
                    self.refresh()
                }
            case .textInsertion:
                // Trusting a process happens in System Settings, so there is no
                // completion to wait on — polling notices the grant.
                prompted.insert(permission)
                system.askForTextInsertion()
            }
        case .systemSettings:
            system.openSettings(permission.settingsURL)
        }
    }

    func beginWatching(interval: TimeInterval = 1) {
        stopWatching()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopWatching() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
