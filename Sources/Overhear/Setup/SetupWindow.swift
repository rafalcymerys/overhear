import AppKit
import SwiftUI

/// The window that carries setup, shown at launch when any of the four
/// requirements is outstanding and reachable from the menu bar until they are
/// all met.
///
/// It replaces two windows that used to appear in sequence — one for
/// permissions, one for a download nobody asked for.
@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow?
    private let setup: SetupCoordinator

    init(setup: SetupCoordinator) {
        self.setup = setup
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
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        setup.permissions.stopWatching()
        window?.close()
    }

    /// Dismissing the window stops the polling. A grant made afterwards is
    /// still noticed the next time anything refreshes, such as opening the
    /// menu bar menu — and a download carries on regardless, since it belongs
    /// to the service rather than to this window.
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            setup.permissions.stopWatching()
        }
    }
}
