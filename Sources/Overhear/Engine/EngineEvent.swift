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
    case error(String)
}

enum EngineError: LocalizedError, Equatable {
    case modelMissing(String)
    case modelInvalid(String)
    case audioUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing(let name):
            return "Model file not found: \(name)"
        case .modelInvalid(let name):
            return "Model could not be read: \(name)"
        case .audioUnavailable(let reason):
            return "Microphone unavailable: \(reason)"
        }
    }
}
