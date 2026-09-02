import AppKit
import SwiftUI
import Combine

@MainActor
final class OverlayController: NSObject {
    private var window: NSWindow?
    private var hostingView: NSHostingView<OverlayView>?
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var onStop: () -> Void
    private var onOpenSettings: () -> Void

    init(appState: AppState, onStop: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.appState = appState
        self.onStop = onStop
        self.onOpenSettings = onOpenSettings
        super.init()
        observe()
    }

    private func observe() {
        appState.$status.sink { [weak self] status in
            Task { @MainActor in
                self?.handleStatusChange(status)
            }
        }.store(in: &cancellables)

        AppSettings.shared.$showOverlay
            .dropFirst()
            .sink { [weak self] show in
                Task { @MainActor in
                    guard let self else { return }
                    if show && self.appState.status.isActive {
                        self.showWindow()
                    } else if !show {
                        self.hideWindow()
                    }
                }
            }.store(in: &cancellables)
    }

    private func handleStatusChange(_ status: EngineStatus) {
        if appState.showCancelled { return }
        switch status {
        case .ready, .listening, .transcribing:
            showWindow()
        case .stopped, .idle, .error, .loading, .installing:
            hideWindow()
        }
    }

    private func showWindow() {
        guard AppSettings.shared.showOverlay else { return }
        if window == nil {
            createWindow()
        }
        positionWindow()
        window?.orderFrontRegardless()
    }

    private func hideWindow() {
        window?.orderOut(nil)
    }

    /// The overlay window never becomes key, which is exactly the case a SwiftUI
    /// `Menu` handles badly, so the options menu is a plain `NSMenu` popped up at
    /// the pointer.
    private func showOptionsMenu() {
        let menu = NSMenu()

        let hide = NSMenuItem(title: "Don't Show the Overlay", action: #selector(hideOverlayForGood), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Turns the setting off rather than hiding the window on its own, so the
    /// overlay stays gone across launches and Settings tells the same story.
    @objc private func hideOverlayForGood() {
        AppSettings.shared.showOverlay = false
    }

    @objc private func showSettings() {
        onOpenSettings()
    }

    private func createWindow() {
        let view = OverlayView(appState: appState, onStop: { [weak self] in
            self?.onStop()
            self?.hideWindow()
        }, onShowOptions: { [weak self] in
            self?.showOptionsMenu()
        })

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.contentView = hostingView

        self.window = window
        self.hostingView = hostingView
    }

    private func positionWindow() {
        guard let window, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let padding: CGFloat = 16
        let x = screenFrame.maxX - window.frame.width - padding
        let y = screenFrame.maxY - window.frame.height - padding
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
