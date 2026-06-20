import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let appState = AppState()
    private var engine: EngineProcess!
    private var overlay: OverlayController!
    private var statusObservation: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon()

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 280)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: StatusView(appState: appState, onToggle: { [weak self] in
                self?.toggleEngine()
            }, onStopDictating: { [weak self] in
                self?.engine.deactivate()
            })
        )

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        engine = EngineProcess(appState: appState)
        overlay = OverlayController(appState: appState, onStop: { [weak self] in
            self?.engine.deactivate()
        })

        statusObservation = appState.$status.sink { [weak self] _ in
            Task { @MainActor in
                self?.updateMenuBarIcon()
            }
        }

        engine.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    private func updateMenuBarIcon() {
        if let button = statusItem?.button {
            let imageName = appState.status.systemImage
            button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Overhear")
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func toggleEngine() {
        if appState.status == .stopped || appState.status == .error {
            engine.start()
        } else {
            engine.stop()
        }
    }
}
