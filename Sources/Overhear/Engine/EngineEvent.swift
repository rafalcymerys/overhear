import Foundation

/// What the engine tells the app about.
///
/// These are the same events the Python engine used to write as JSON lines, kept
/// name for name: the state machine in `AppState`, the overlay and the menu bar
/// icon were all written against this vocabulary and none of them needed to
/// change when the engine moved in-process.
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
