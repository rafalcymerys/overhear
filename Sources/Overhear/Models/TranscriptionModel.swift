import Foundation

/// A transcription backend — the thing that turns audio into text.
///
/// Named "engine" in the interface, where it is the heading a group of models
/// sits under. The dictation engine that `EngineController` starts and stops is
/// a different thing entirely; this one is only ever a property of a model.
enum TranscriptionEngineKind: String, Codable, CaseIterable, Hashable {
    case whisper
    case parakeet

    var displayName: String {
        switch self {
        case .whisper: return "Whisper"
        case .parakeet: return "Parakeet"
        }
    }

    /// The directory this engine's weights live in, beneath Application
    /// Support. Renaming a case orphans hundreds of megabytes on every install
    /// that already downloaded something.
    var directoryName: String { rawValue }

    /// Whether this engine can render speech in an unselected language as
    /// English. Whisper has a translate task; Parakeet has none, so the setting
    /// is hidden rather than left to do nothing.
    var canTranslate: Bool {
        switch self {
        case .whisper: return true
        case .parakeet: return false
        }
    }

    /// The few words under the group heading, saying what the engine is for.
    var summary: String {
        switch self {
        case .whisper: return "multilingual · CoreML"
        case .parakeet: return "fastest · CoreML"
        }
    }
}

/// One model the user can download, activate and remove.
///
/// `variant` is what the engine is asked to load; everything else is what the
/// interface shows. The two are kept apart deliberately — the pane must never
/// put `openai_whisper-base` in front of anyone.
struct TranscriptionModel: Identifiable, Hashable, Sendable {
    let id: String
    let engine: TranscriptionEngineKind

    /// The name within its engine, such as "Base". The group heading supplies
    /// the rest.
    let name: String

    /// What the engine loads. A WhisperKit variant for `.whisper`.
    let variant: String

    /// Roughly what the download costs, for the row and the removal
    /// confirmation. The figure on disk afterwards comes from measuring, not
    /// from this.
    let downloadSize: Int64

    /// The languages this model can transcribe, or `nil` when it can transcribe
    /// every language Overhear knows about.
    let languageCodes: Set<String>?

    /// A handful of words on what this model is good and bad at, such as
    /// "fastest" or "most accurate". Nothing when it is the unremarkable middle.
    let note: String?

    var displayName: String { "\(engine.displayName) \(name)" }

    var supportsEveryLanguage: Bool { languageCodes == nil }

    func supports(_ code: String) -> Bool {
        guard let languageCodes else { return true }
        return languageCodes.contains(code)
    }

    var supportedLanguages: [RecognitionLanguage] {
        guard let languageCodes else { return RecognitionLanguage.all }
        return RecognitionLanguage.all.filter { languageCodes.contains($0.code) }
    }

    /// How the languages read in the card: "99 languages", or "English only"
    /// when there is just the one.
    var languageSummary: String {
        let supported = supportedLanguages
        if supported.count == 1 {
            return "\(supported[0].name) only"
        }
        return "\(supported.count) languages"
    }
}
