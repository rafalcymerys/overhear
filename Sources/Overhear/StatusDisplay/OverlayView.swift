import SwiftUI

struct OverlayView: View {
    @ObservedObject var appState: AppState
    var onStop: () -> Void
    var onShowOptions: () -> Void

    private var showStopButton: Bool {
        appState.status.isActive
    }

    private var darkBackground: Bool {
        appState.status == .ready && !appState.showCancelled
    }

    private var markState: MarkState {
        MarkState(status: appState.status,
                  showCancelled: appState.showCancelled,
                  needsSetup: appState.needsSetup)
    }

    private var label: String? {
        if appState.showCancelled {
            return "Cancelled"
        }
        switch appState.status {
        case .ready: return "Ready"
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // One mark instance across every state, so it crossfades here the same
            // way it does in the menu bar rather than being torn down and rebuilt.
            HStack(spacing: 6) {
                if let label {
                    LiveMark(state: markState)
                        .frame(width: 14, height: 14)
                    Text(label)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundColor(appState.showCancelled ? .red : .primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showStopButton {
                HStack(spacing: 6) {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                            .foregroundColor(darkBackground ? .black : .white)
                            .frame(width: 26, height: 26)
                            .background(darkBackground ? Color.white.opacity(0.85) : Color.primary.opacity(0.85))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Stop listening")

                    // Quieter than stop: hiding the overlay is a preference, not
                    // the thing you came to the panel to do.
                    Button(action: onShowOptions) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor((darkBackground ? Color.white : Color.primary).opacity(0.7))
                            .frame(width: 22, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("More options")
                }
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
