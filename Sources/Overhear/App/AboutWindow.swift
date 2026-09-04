import AppKit
import SwiftUI

/// The About window.
///
/// Hand-built rather than `NSApp.orderFrontStandardAboutPanel`, which cannot
/// carry a button — and the licenses Overhear has to ship are far too long to
/// live in that panel's credits field, so they need a window of their own and
/// something to open it.
@MainActor
final class AboutWindowController: NSObject {
    private(set) var window: NSWindow?
    private let acknowledgements = AcknowledgementsWindowController()

    func show() {
        if window == nil {
            window = makeWindow()
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        acknowledgements.close()
    }

    private func makeWindow() -> NSWindow {
        let view = AboutView(info: AppInfo.current) { [weak self] in
            self?.acknowledgements.show()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        // Untitled, like the panel it replaces: the app's own name is already
        // the largest thing in the window.
        window.title = ""
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

/// What the About window says about this build.
struct AppInfo {
    let name: String
    let version: String
    let copyright: String

    static var current: AppInfo {
        let info = infoDictionary()
        return AppInfo(
            name: info["CFBundleName"] as? String ?? "Overhear",
            version: info["CFBundleShortVersionString"] as? String ?? "",
            copyright: info["NSHumanReadableCopyright"] as? String ?? ""
        )
    }

    /// The bundle's Info.plist, falling back to the one in the source tree.
    ///
    /// A `swift run` build or a test run has no bundle of ours to read, and an
    /// About window that says nothing is worse than one reading the plist that
    /// will be baked into the app anyway.
    ///
    /// Identified by bundle identifier rather than by probing for a key: under
    /// `swift test` the main bundle is xctest, whose embedded plist carries a
    /// copyright of its own and so answers any such probe convincingly.
    private static func infoDictionary() -> [String: Any] {
        if Bundle.main.bundleIdentifier == "com.cymerys.overhear",
           let info = Bundle.main.infoDictionary {
            return info
        }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return [:]
        }
        return plist
    }
}

struct AboutView: View {
    let info: AppInfo
    let onShowAcknowledgements: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text(info.name)
                    .font(.system(size: 20, weight: .medium))
                if !info.version.isEmpty {
                    Text("Version \(info.version)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Acknowledgements…", action: onShowAcknowledgements)

            if !info.copyright.isEmpty {
                Text(info.copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(width: 320)
    }
}
