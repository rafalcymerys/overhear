import SwiftUI

struct MenuBarIcon: View {
    @ObservedObject var appState: AppState

    private var isActive: Bool {
        switch appState.status {
        case .ready, .listening, .transcribing: return true
        default: return false
        }
    }

    private var bgColor: Color {
        if appState.showCancelled {
            return Color.red
        }
        switch appState.status {
        case .ready, .listening:
            return Color(red: 1.0, green: 0.58, blue: 0.0)
        case .transcribing:
            return Color(red: 0.85, green: 0.45, blue: 0.0)
        default:
            return .clear
        }
    }

    var body: some View {
        ZStack {
            if isActive {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(bgColor)
                    .frame(width: 22, height: 22)
            }

            if appState.showCancelled {
                Image(systemName: "stop.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
            } else if appState.status == .listening {
                MenuBarAudioBars()
            } else if appState.status == .ready {
                MenuBarStaticBars()
            } else if appState.status == .transcribing {
                ProgressView()
                    .scaleEffect(0.5)
                    .colorScheme(.dark)
            } else {
                Image(systemName: appState.status.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
        .frame(width: 22, height: 22)
    }
}

struct MenuBarStaticBars: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 3, height: 5)
            }
        }
    }
}

struct MenuBarAudioBars: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 3, height: animating ? barHeight(i) : 4)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
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
