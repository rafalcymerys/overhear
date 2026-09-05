import Foundation
import SwiftUI

enum EngineStatus: String {
    case stopped = "Stopped"
    case loading = "Loading models…"
    case idle = "Idle"
    case ready = "Ready"
    case listening = "Listening…"
    case transcribing = "Transcribing…"
    case error = "Error"

    var color: Color {
        switch self {
        case .stopped: return .gray
        case .loading: return .orange
        case .idle: return .green
        case .ready, .listening: return .red
        case .transcribing: return .blue
        case .error: return .red
        }
    }

    var systemImage: String {
        switch self {
        case .stopped: return "mic.slash"
        case .loading: return "circle.dashed"
        case .idle: return "mic"
        case .ready, .listening: return "mic.fill"
        case .transcribing: return "text.bubble"
        case .error: return "exclamationmark.triangle"
        }
    }

    var isActive: Bool {
        switch self {
        case .ready, .listening, .transcribing: return true
        default: return false
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var status: EngineStatus = .stopped

    /// Whether something setup covers is still missing — no model, or a
    /// permission not granted.
    ///
    /// Kept here rather than read from `SetupCoordinator` because the mark is
    /// drawn from app state alone, and the two places that draw it should not
    /// have to know what a setup requirement is.
    @Published var needsSetup: Bool = false

    @Published var errorMessage: String?
    @Published var recentTranscriptions: [String] = []
    @Published var showCancelled: Bool = false
    private var cancelledTimer: Timer?

    func addTranscription(_ text: String) {
        recentTranscriptions.insert(text, at: 0)
        if recentTranscriptions.count > 5 {
            recentTranscriptions.removeLast()
        }
    }

    func triggerCancelled() {
        showCancelled = true
        cancelledTimer?.invalidate()
        cancelledTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.showCancelled = false
            }
        }
    }
}
