import Foundation
import SwiftUI

enum EngineStatus: String {
    case stopped = "Stopped"
    case loading = "Loading models…"
    case ready = "Ready"
    case listening = "Waiting for wake word…"
    case wakeWordDetected = "Wake word detected"
    case recording = "Recording…"
    case transcribing = "Transcribing…"
    case error = "Error"

    var color: Color {
        switch self {
        case .stopped: return .gray
        case .loading: return .orange
        case .ready, .listening: return .green
        case .wakeWordDetected, .recording: return .red
        case .transcribing: return .blue
        case .error: return .red
        }
    }

    var systemImage: String {
        switch self {
        case .stopped: return "mic.slash"
        case .loading: return "arrow.down.circle"
        case .ready, .listening: return "mic"
        case .wakeWordDetected, .recording: return "mic.fill"
        case .transcribing: return "text.bubble"
        case .error: return "exclamationmark.triangle"
        }
    }

    var isActive: Bool {
        switch self {
        case .listening, .wakeWordDetected, .recording, .transcribing: return true
        default: return false
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var status: EngineStatus = .stopped
    @Published var lastTranscription: String = ""
    @Published var errorMessage: String?
    @Published var transcriptionCount: Int = 0
}
