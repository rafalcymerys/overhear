import AppKit
import Combine
import SwiftUI

/// The window that carries setup, shown at launch when any of the four
/// requirements is outstanding and reachable from the menu bar until they are
/// all met.
///
/// It replaces two windows that used to appear in sequence — one for
/// permissions, one for a download nobody asked for.
@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    /// The AppKit calls that put the window in front of the user. Injected
    /// because a test process is never given the front, so the asking is the
    /// only part of this there is to assert on.
    struct System {
        var bringToFront: @MainActor (NSWindow) -> Void = { window in
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private(set) var window: NSWindow?
    private let setup: SetupCoordinator
    private let system: System
    /// What the permissions said at the last emission, so an answer can be told
    /// from a poll reading back what it already knew.
    private var lastSeenStates: [Permission: PermissionState] = [:]
    private var answerObservation: AnyCancellable?

    init(setup: SetupCoordinator, system: System = System()) {
        self.setup = setup
        self.system = system
    }

    func show() {
        if window == nil {
            let view = SetupView(
                setup: setup,
                permissions: setup.permissions,
                models: setup.models,
                wakeWords: setup.wakeWords,
                onQuit: { NSApp.terminate(nil) }
            )

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Overhear Setup"
            let hosting = NSHostingView(rootView: view)
            window.contentView = hosting
            // Cards open and close and the explanations wrap to however many
            // lines they need, so let the content decide the height rather than
            // clipping it.
            window.setContentSize(hosting.fittingSize)
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }

        setup.refresh()
        setup.permissions.beginWatching()
        watchForAnswers()
        bringToFront()
    }

    func close() {
        answerObservation = nil
        setup.permissions.stopWatching()
        window?.close()
    }

    private func bringToFront() {
        guard let window else { return }
        system.bringToFront(window)
    }

    /// macOS takes the front away for as long as one of its permission dialogs
    /// is up, and hands it back to whichever app held it before rather than to
    /// the one that asked — often the browser this window was sitting in front
    /// of. So the window claims it back itself, as soon as an answer lands.
    ///
    /// The answer arrives a turn of the loop after the assignment that carries
    /// it, so `isComplete` has settled by the time it is read. A grant that
    /// finishes setup closes the window instead, and pulling it forward on the
    /// way out would take the front from whatever the user went back to.
    private func watchForAnswers() {
        lastSeenStates = setup.permissions.states
        answerObservation = setup.permissions.$states
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] states in
                guard let self else { return }
                let previous = lastSeenStates
                lastSeenStates = states
                guard Self.wasAnswered(from: previous, to: states) else { return }
                guard !setup.isComplete, window?.isVisible == true else { return }
                bringToFront()
            }
    }

    /// Whether a permission that was still open has been answered — the dialog
    /// Overhear put up has gone, whichever button was pressed.
    ///
    /// A permission leaving `.granted` is a revocation, made in System Settings
    /// where the user still is. Nothing was asked for there, so nothing should
    /// jump in front of the switch they are working.
    static func wasAnswered(from previous: [Permission: PermissionState],
                            to current: [Permission: PermissionState]) -> Bool {
        Permission.allCases.contains { permission in
            (previous[permission] ?? .notDetermined) == .notDetermined
                && (current[permission] ?? .notDetermined) != .notDetermined
        }
    }

    /// Dismissing the window stops the polling. A grant made afterwards is
    /// still noticed the next time anything refreshes, such as opening the
    /// menu bar menu — and a download carries on regardless, since it belongs
    /// to the service rather than to this window.
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            answerObservation = nil
            setup.permissions.stopWatching()
        }
    }
}
