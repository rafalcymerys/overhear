import SwiftUI

struct StatusView: View {
    @ObservedObject var appState: AppState
    var onToggle: () -> Void
    var onStopDictating: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Overhear")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(appState.status.color)
                    .frame(width: 10, height: 10)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: appState.status.systemImage)
                        .foregroundColor(appState.status.color)
                        .frame(width: 20)
                    Text(appState.status.rawValue)
                        .font(.system(.body, design: .rounded))
                }

                if let error = appState.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(3)
                }
            }

            Divider()

            if !appState.lastTranscription.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last dictation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(appState.lastTranscription)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(4)
                        .textSelection(.enabled)
                }

                Text("\(appState.transcriptionCount) total")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()
            }

            HStack {
                if appState.status == .dictating || appState.status == .transcribing {
                    Button(action: onStopDictating) {
                        Text("Stop Dictating")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .tint(.red)
                } else {
                    Button(action: onToggle) {
                        Text(appState.status.isActive || appState.status == .loading ? "Stop Engine" : "Start")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .frame(width: 320)
    }
}
