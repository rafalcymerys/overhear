import AppKit
import SwiftUI
import Combine

@MainActor
final class OverlayController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<OverlayView>?
    private let appState: AppState
    private let overlayState = OverlayState()
    private var cancellables = Set<AnyCancellable>()
    private var dismissTimer: Timer?
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

        appState.$lastTranscription
            .dropFirst()
            .sink { [weak self] text in
                Task { @MainActor in
                    guard let self, !text.isEmpty else { return }
                    self.overlayState.transcribedText = text
                    self.overlayState.phase = .result
                    self.scheduleDismiss()
                }
            }.store(in: &cancellables)
    }

    private func handleStatusChange(_ status: EngineStatus) {
        dismissTimer?.invalidate()
        dismissTimer = nil

        switch status {
        case .dictating:
            overlayState.phase = .listening
            overlayState.transcribedText = ""
            showWindow()
        case .hearing:
            overlayState.phase = .hearing
            showWindow()
        case .transcribing:
            overlayState.phase = .transcribing
            showWindow()
        case .listening, .stopped, .ready, .error, .loading:
            if overlayState.phase != .result {
                hideWindow()
            }
        }
    }

    private func scheduleDismiss() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // If still dictating, go back to listening indicator
                if self.appState.status == .dictating {
                    self.overlayState.phase = .listening
                } else {
                    self.hideWindow()
                }
            }
        }
    }

    private func showWindow() {
        if window == nil {
            createWindow()
        }
        positionWindow()
        window?.orderFrontRegardless()
    }

    private func hideWindow() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        window?.orderOut(nil)
        overlayState.phase = .hidden
    }

    private func createWindow() {
        let view = OverlayView(state: overlayState, onStop: { [weak self] in
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

enum OverlayPhase {
    case hidden, listening, hearing, transcribing, result
}

@MainActor
final class OverlayState: ObservableObject {
    @Published var phase: OverlayPhase = .hidden
    @Published var transcribedText: String = ""
}

struct OverlayView: View {
    @ObservedObject var state: OverlayState
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                switch state.phase {
                case .listening:
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                        Text("Ready")
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundColor(.white)
                    }
                case .hearing:
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
                case .result:
                    Text(state.transcribedText)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                        .foregroundColor(.primary)
                case .hidden:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if state.phase == .listening || state.phase == .hearing || state.phase == .transcribing {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                        .foregroundColor(state.phase == .listening ? .black : .white)
                        .frame(width: 26, height: 26)
                        .background(state.phase == .listening ? Color.white.opacity(0.85) : Color.primary.opacity(0.85))
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
                    .opacity(state.phase == .listening ? 0 : 1)
                Color.black.opacity(0.3)
                    .opacity(state.phase == .listening ? 1 : 0)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeInOut(duration: 0.35), value: state.phase)
    }
}

struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
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
