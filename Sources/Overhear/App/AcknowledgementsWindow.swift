import AppKit

/// A scrolling window over the bundled license notice.
///
/// Plain `NSTextView` in an `NSScrollView` rather than SwiftUI: the text runs to
/// something like eighty kilobytes of licenses, and a SwiftUI `ScrollView` of
/// `Text` lays all of it out at once to measure itself, which takes long enough
/// to be visible. It is also monospaced on purpose — the Apache license is
/// indented by hand and reflows into a mess in a proportional font.
@MainActor
final class AcknowledgementsWindowController: NSObject {
    private(set) var window: NSWindow?

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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Acknowledgements"
        window.contentView = makeTextView()
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func makeTextView() -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        // Selectable so a reader can copy a license out, which is the one thing
        // anyone actually wants to do with this window.
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.string = Acknowledgements.text() ?? Self.missing
        return scrollView
    }

    /// Shown when the generated resource isn't there — a development build run
    /// straight from Xcode without the plugin having produced it, chiefly.
    private static let missing = """
        The acknowledgements file is generated at build time and is missing from \
        this build.

        Run `swift build` and try again, or read Resources/acknowledgements.json \
        in the project for the list of bundled dependencies.
        """
}
