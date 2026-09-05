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
        /// `orderFrontRegardless` rather than `makeKeyAndOrderFront` alone:
        /// since macOS 14 an app that is not the active one cannot take the
        /// front by asking, and an accessory app asking while System Settings
        /// is in front of it is refused. Ordering a window above the other
        /// app's windows needs no such permission, and `activate` is left in
        /// for the case where it is ours to take.
        var bringToFront: @MainActor (NSWindow) -> Void = { window in
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate()
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
        window?.level = .normal
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
                guard !setup.isComplete, let window, window.isVisible else { return }
                // Above the other app's windows rather than merely in front of
                // them now: closing System Settings hands the front to whatever
                // was behind it, and a normal window would go straight back
                // under the browser it was hidden by. Dropped again in
                // windowDidBecomeKey, once the window is the user's.
                window.level = .floating
                bringToFront()
            }
    }

    /// Whether an answer has arrived for a permission that was outstanding —
    /// the dialog Overhear put up has gone, or the switch in System Settings
    /// has been thrown, whichever the card sent the user to.
    ///
    /// Anything but a revocation counts, which a dismissed dialog made matter:
    /// it settles the microphone at denied, and the grant that follows it in
    /// System Settings is `denied` to `granted` rather than an answer to
    /// anything still open.
    ///
    /// A permission leaving `.granted` is that revocation, made in System
    /// Settings where the user still is. Nothing was asked for there, so
    /// nothing jumps in front of the switch they are working.
    static func wasAnswered(from previous: [Permission: PermissionState],
                            to current: [Permission: PermissionState]) -> Bool {
        Permission.allCases.contains { permission in
            let before = previous[permission] ?? .notDetermined
            return before != (current[permission] ?? .notDetermined) && before != .granted
        }
    }

    /// The window is the user's again, so it stops floating over their other
    /// apps and goes back to being one window among them.
    ///
    /// Only once Overhear is the app in front, though. A window can be handed
    /// key status while the app behind System Settings is still the app behind
    /// System Settings, and dropping the level there would put it back under
    /// the browser the moment the front moved on.
    nonisolated func windowDidBecomeKey(_ notification: Notification) {
        Task { @MainActor in
            guard NSApp.isActive else { return }
            window?.level = .normal
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
