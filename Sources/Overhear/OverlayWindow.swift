import AppKit
import SwiftUI
import Combine

@MainActor
final class OverlayController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<OverlayView>?
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()
    private var onStop: () -> Void

    init(appState: AppState, onStop: @escaping () -> Void) {
        self.appState = appState
        self.onStop = onStop
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
        case .stopped, .idle, .error, .loading:
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

    private func createWindow() {
        let view = OverlayView(appState: appState, onStop: { [weak self] in
            self?.onStop()
            self?.hideWindow()
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

struct OverlayView: View {
    @ObservedObject var appState: AppState
    var onStop: () -> Void

    private var showStopButton: Bool {
        appState.status.isActive
    }

    private var darkBackground: Bool {
        appState.status == .ready && !appState.showCancelled
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if appState.showCancelled {
                    OverlayShakeBars()
                } else {
                    switch appState.status {
                    case .ready:
                        HStack(spacing: 6) {
                            HStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.primary)
                                        .frame(width: 3, height: 4)
                                }
                            }
                            .frame(width: 14, height: 14)
                            Text("Ready")
                                .font(.system(.body, design: .rounded, weight: .medium))
                        }
                    case .listening:
                        HStack(spacing: 6) {
                            AudioBars()
                            Text("Listening…")
                                .font(.system(.body, design: .rounded, weight: .medium))
                        }
                    case .transcribing:
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 10, height: 10)
                            Text("Transcribing…")
                                .font(.system(.body, design: .rounded, weight: .medium))
                        }
                    default:
                        EmptyView()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showStopButton {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                        .foregroundColor(darkBackground ? .black : .white)
                        .frame(width: 26, height: 26)
                        .background(darkBackground ? Color.white.opacity(0.85) : Color.primary.opacity(0.85))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 280)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                    .opacity(darkBackground ? 0 : 1)
                Color.black.opacity(0.3)
                    .opacity(darkBackground ? 1 : 0)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeInOut(duration: 0.35), value: appState.status)
        .animation(.easeInOut(duration: 0.35), value: appState.showCancelled)
    }
}

struct AudioBars: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary)
                    .frame(width: 3, height: animating ? barHeight(i) : 4)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .frame(width: 14, height: 14)
        .onAppear { animating = true }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        switch index {
        case 0: return 10
        case 1: return 14
        case 2: return 8
        default: return 10
        }
    }
}

struct OverlayShakeBars: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.red)
                        .frame(width: 3, height: 4)
                }
            }
            .frame(width: 14, height: 14)
            .offset(x: animating ? 3 : -3)
            .animation(
                .easeInOut(duration: 0.08)
                    .repeatForever(autoreverses: true),
                value: animating
            )
            Text("Cancelled")
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundColor(.red)
        }
        .onAppear { animating = true }
    }
}
