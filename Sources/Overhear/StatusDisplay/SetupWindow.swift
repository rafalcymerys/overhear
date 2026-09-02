import AppKit
import SwiftUI

/// The window shown while the app fetches its wake word models on first launch.
///
/// A few megabytes over a slow connection is still long enough that a silent
/// menu bar icon reads as a broken app, so setup says what it is doing.
@MainActor
final class SetupWindowController {
    private var window: NSWindow?
    private let setup: WakeWordSetup
    private let onRetry: () -> Void

    init(setup: WakeWordSetup, onRetry: @escaping () -> Void) {
        self.setup = setup
        self.onRetry = onRetry
    }

    func show() {
        if window == nil {
            let view = SetupView(
                setup: setup,
                onRetry: { [weak self] in self?.onRetry() },
                onQuit: { NSApp.terminate(nil) }
            )

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
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
}

struct SetupView: View {
    @ObservedObject var setup: WakeWordSetup
    var onRetry: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Setting up Overhear")
                .font(.system(.title3, design: .rounded, weight: .semibold))

            if let failure = setup.failure {
                Text(failure)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Spacer()
                    Button("Quit", action: onQuit)
                    Button("Try Again", action: onRetry)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Overhear is downloading the models it listens with. This happens once.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                    Text(setup.step)
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
