import Foundation

/// What the engine tells the app about.
///
/// The whole contract between the engine and the UI. `AppState`, the overlay and
/// the menu bar icon are driven entirely by these cases, so nothing above
/// `EngineController` knows how audio is captured or how a model is run.
enum EngineEvent: Equatable {
    case status(String)
    case idle
    case ready
    case speechStart
    case transcribing
    case transcription(String)
    case languageDetected(String)
    case wakeWordCancel
    case warning(String)
    /// The engine is down. Something it had to load did not, or too many
    /// batches failed in a row, and nothing it does on its own will change
    /// that.
    case failed(String)
    /// One batch could not be transcribed. Dictation carries on, so this is
    /// about the utterance that was lost rather than about the app.
    case batchFailed(String)
}

enum EngineError: LocalizedError, Equatable {
    case modelInvalid(String)
    case audioUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .modelInvalid(let name):
            return "Model could not be read: \(name)"
        case .audioUnavailable(let reason):
            return "Microphone unavailable: \(reason)"
        }
    }
}
