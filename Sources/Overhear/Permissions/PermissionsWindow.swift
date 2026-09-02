import AppKit
import SwiftUI

/// The window shown at launch when macOS hasn't granted Overhear what it needs.
/// Dictation can't start without both permissions, so this comes before setup
/// and before the engine rather than failing quietly in the menu bar.
@MainActor
final class PermissionsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let permissions: PermissionsService

    init(permissions: PermissionsService) {
        self.permissions = permissions
    }

    func show() {
        if window == nil {
            let view = PermissionsView(
                permissions: permissions,
                onGrant: { [weak self] permission in self?.permissions.request(permission) },
                onQuit: { NSApp.terminate(nil) }
            )

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Overhear Permissions"
            let hosting = NSHostingView(rootView: view)
            window.contentView = hosting
            // The rows wrap to however many lines the explanations need, so let
            // the content decide the height rather than clipping it.
            window.setContentSize(hosting.fittingSize)
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }

        permissions.refresh()
        permissions.beginWatching()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        permissions.stopWatching()
        window?.close()
    }

    /// Dismissing the window stops the polling — a grant made afterwards is
    /// still noticed the next time anything refreshes, such as opening the menu.
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            permissions.stopWatching()
        }
    }
}

struct PermissionsView: View {
    @ObservedObject var permissions: PermissionsService
    var onGrant: (Permission) -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Overhear needs two permissions")
                .font(.system(.title3, design: .rounded, weight: .semibold))

            ForEach(Permission.allCases) { permission in
                PermissionRow(
                    permission: permission,
                    state: permissions.state(of: permission),
                    request: permissions.nextRequest(for: permission),
                    isNext: permissions.missing.first == permission,
                    onGrant: { onGrant(permission) }
                )
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Quit", action: onQuit)
            }
        }
        .padding(20)
        .frame(width: 460, alignment: .topLeading)
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let state: PermissionState
    let request: PermissionRequest
    /// The first permission still missing gets the default-action styling, so
    /// the window reads as one step after another.
    let isNext: Bool
    var onGrant: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: state == .granted ? "checkmark.circle.fill" : permission.symbol)
                    .foregroundColor(state == .granted ? .green : .secondary)
                Text(permission.title)
                    .font(.system(.body, weight: .medium))
            }

            Text(permission.explanation)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if state == .granted {
                Text("Granted")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                Button(buttonTitle, action: onGrant)
                    .modifier(DefaultAction(enabled: isNext))
            }
        }
    }

    private var buttonTitle: String {
        request == .systemDialog ? permission.buttonTitle : "Open System Settings"
    }
}

/// `keyboardShortcut` has no conditional form, so wrap it.
private struct DefaultAction: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.keyboardShortcut(.defaultAction)
        } else {
            content
        }
    }
}

private extension Permission {
    var symbol: String {
        switch self {
        case .microphone: return "mic"
        case .textInsertion: return "keyboard"
        }
    }
}
