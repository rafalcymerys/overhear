import AppKit
import SwiftUI

/// The panes, in the order they appear in the toolbar.
enum SettingsTab: String, CaseIterable {
    case general
    case transcription
    case hotWords

    var title: String {
        switch self {
        case .general: return "General"
        case .transcription: return "Transcription"
        case .hotWords: return "Hot Words"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .transcription: return "text.bubble"
        case .hotWords: return "waveform"
        }
    }

    /// Every pane is this wide; only the height varies.
    static let width: CGFloat = 460

    /// How tall a pane may grow before it scrolls instead.
    ///
    /// Every pane sizes to its content, so the window is never taller than what
    /// it holds — Hot Words grows as custom words are installed, and
    /// Transcription as engines and models are added. The cap is what stops
    /// either from growing past a window that fits on a laptop screen; the
    /// language list, which is longer than any window should be, lives in a
    /// popover rather than in a pane.
    var maximumHeight: CGFloat {
        switch self {
        case .general, .hotWords: return 600
        case .transcription: return 700
        }
    }

    var itemIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue)
    }

    /// - Parameter appState: what the Transcription pane reports the model's
    ///   load state from. Nil where there is no engine to report on — a test,
    ///   chiefly — which reads as loaded rather than as broken.
    @MainActor
    func makeContentView(appState: AppState? = nil) -> NSView {
        switch self {
        case .general:
            return NSHostingView(rootView: GeneralSettingsView().frame(width: Self.width))
        case .transcription:
            return NSHostingView(rootView: TranscriptionSettingsView(appState: appState).frame(width: Self.width))
        case .hotWords:
            return NSHostingView(rootView: HotWordSettingsView().frame(width: Self.width))
        }
    }

    /// What the window's content rect should be for a freshly built pane.
    @MainActor
    func contentSize(of view: NSView) -> NSSize {
        view.layoutSubtreeIfNeeded()
        let height = min(view.fittingSize.height, maximumHeight)
        return NSSize(width: Self.width, height: height)
    }
}

/// The settings window: a toolbar of panes above one pane at a time.
///
/// Built on a plain window and toolbar rather than `NSTabViewController`, which
/// sizes itself through Auto Layout to fit its largest tab — that leaves the
/// short General pane rattling around in a window sized for the model list, and
/// it overrides any frame set by hand.
@MainActor
final class SettingsWindowController: NSObject {
    /// Exposed for tests, which assert on the window's title and size as
    /// panes are selected.
    private(set) var window: NSWindow?
    private(set) var selected: SettingsTab = .general

    /// Passed to the Transcription pane so it can say whether the active model
    /// is loaded.
    private let appState: AppState?

    init(appState: AppState? = nil) {
        self.appState = appState
        super.init()
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let content = selected.makeContentView(appState: appState)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: selected.contentSize(of: content)),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.selectedItemIdentifier = selected.itemIdentifier

        window.toolbar = toolbar
        // The System Settings look: centred icon-and-label items, no title bar
        // crowding them.
        window.toolbarStyle = .preference
        window.title = selected.title
        window.contentView = content
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    @objc
    private func selectTab(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(rawValue: sender.itemIdentifier.rawValue) else { return }
        select(tab)
    }

    /// Swap panes the way macOS settings windows do: blank the window, resize
    /// it, then show the new pane.
    ///
    /// The blank matters. Animating a resize with the old pane still in place
    /// stretches and clips it on the way, which reads as a glitch; leaving the
    /// window empty for the couple of frames it takes reads as deliberate.
    func select(_ tab: SettingsTab) {
        guard tab != selected, let window else { return }
        selected = tab

        // Built before the resize so the window animates to the size the pane
        // actually needs rather than to a guess.
        let content = tab.makeContentView(appState: appState)
        let target = frame(for: tab, sized: tab.contentSize(of: content), in: window)
        window.title = tab.title
        window.contentView = NSView()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            // The pane can have changed again if the user clicked twice before
            // the animation finished; the last click wins.
            guard let self, self.selected == tab else { return }
            window.contentView = content
        }
    }

    /// The window frame for a pane, anchored to the title bar.
    ///
    /// Growing downwards rather than from the bottom edge keeps the window
    /// where the user put it, instead of appearing to jump up the screen.
    private func frame(for tab: SettingsTab, sized size: NSSize, in window: NSWindow) -> NSRect {
        let content = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var target = window.frame
        target.origin.y += target.height - content.height
        target.size = content.size
        return target
    }
}

extension SettingsWindowController: NSToolbarDelegate {
    nonisolated func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.itemIdentifier)
    }

    nonisolated func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    /// What makes the items behave as a picker rather than as buttons: the
    /// selected one stays highlighted.
    nonisolated func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = SettingsTab(rawValue: itemIdentifier.rawValue) else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.paletteLabel = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(selectTab(_:))
        return item
    }
}
