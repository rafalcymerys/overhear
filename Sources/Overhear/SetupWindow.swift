import AppKit
import SwiftUI

/// The window shown while the app builds its Python environment on first
/// launch. Setup downloads a few hundred megabytes of models, so it needs to
/// say what is happening rather than leave a silent menu bar icon.
@MainActor
final class SetupWindowController {
    private var window: NSWindow?
    private let installer: EngineInstaller
    private let onRetry: () -> Void

    init(installer: EngineInstaller, onRetry: @escaping () -> Void) {
        self.installer = installer
        self.onRetry = onRetry
    }

    func show() {
        if window == nil {
            let view = SetupView(
                installer: installer,
                onRetry: { [weak self] in self?.onRetry() },
                onShowLog: { [weak self] in self?.revealLog() },
                onQuit: { NSApp.terminate(nil) }
            )

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Overhear Setup"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    private func revealLog() {
        let log = EngineInstaller.supportDirectory.appendingPathComponent("install.log")
        guard FileManager.default.fileExists(atPath: log.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([log])
    }
}

struct SetupView: View {
    @ObservedObject var installer: EngineInstaller
    var onRetry: () -> Void
    var onShowLog: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Setting up Overhear")
                .font(.system(.title3, design: .rounded, weight: .semibold))

            if let failure = installer.failure {
                Text(failure)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Button("Show Log", action: onShowLog)
                    Spacer()
                    Button("Quit", action: onQuit)
                    Button("Try Again", action: onRetry)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text(installer.reason.explanation)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                    Text(installer.step)
                        .font(.callout)
                }

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    Button("Quit", action: onQuit)
                }
            }
        }
        .padding(20)
        .frame(width: 420, alignment: .topLeading)
    }
}
