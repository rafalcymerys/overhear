import Combine
import Foundation

enum EngineStatus: String {
    case stopped = "Stopped"
    case loading = "Loading models…"
    case idle = "Idle"
    case ready = "Ready"
    case listening = "Listening…"
    case transcribing = "Transcribing…"
    case error = "Error"

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

    /// A batch that could not be transcribed, for the second it is shown.
    ///
    /// Separate from `errorMessage`, which means the engine is down and stays
    /// until something is done about it. This one is about the utterance that
    /// was lost, so it belongs on the overlay and clears itself.
    @Published var showFailedBatch: Bool = false
    private var failedBatchTimer: Timer?

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

    func triggerFailedBatch() {
        showFailedBatch = true
        failedBatchTimer?.invalidate()
        failedBatchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.showFailedBatch = false
            }
        }
    }
}
