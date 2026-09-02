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

    var supportedLanguages: [WhisperLanguage] {
        guard let languageCodes else { return WhisperLanguage.all }
        return WhisperLanguage.all.filter { languageCodes.contains($0.code) }
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

/// Every model Overhear can run, in the order the pane lists them.
///
/// Whisper only, for now. `TranscriptionEngineKind` carries `.parakeet` and
/// every path below is written against the engine rather than against Whisper,
/// but no Parakeet model is offered until there is a transcriber that can run
/// one — a row that downloads six hundred megabytes and then cannot transcribe
/// would be worse than no row.
enum ModelCatalog {
    static let whisperTiny = TranscriptionModel(
        id: "whisper-tiny",
        engine: .whisper,
        name: "Tiny",
        variant: "tiny",
        downloadSize: 75 * 1_000_000,
        languageCodes: nil,
        note: "fastest"
    )

    static let whisperBase = TranscriptionModel(
        id: "whisper-base",
        engine: .whisper,
        name: "Base",
        variant: "base",
        downloadSize: 145 * 1_000_000,
        languageCodes: nil,
        note: nil
    )

    /// Whisper's English-only build of Base. The same size and speed, more
    /// accurate on English, and unable to transcribe anything else — which is
    /// what makes the language selection narrow when it is activated.
    static let whisperBaseEnglish = TranscriptionModel(
        id: "whisper-base-en",
        engine: .whisper,
        name: "Base English",
        variant: "base.en",
        downloadSize: 145 * 1_000_000,
        languageCodes: ["en"],
        note: nil
    )

    static let whisperSmall = TranscriptionModel(
        id: "whisper-small",
        engine: .whisper,
        name: "Small",
        variant: "small",
        downloadSize: 480 * 1_000_000,
        languageCodes: nil,
        note: nil
    )

    static let whisperLargeTurbo = TranscriptionModel(
        id: "whisper-large-v3-turbo",
        engine: .whisper,
        name: "Large v3 Turbo",
        variant: "large-v3-v20240930_turbo",
        downloadSize: 1_600 * 1_000_000,
        languageCodes: nil,
        note: "most accurate"
    )

    static let all: [TranscriptionModel] = [
        whisperTiny, whisperBase, whisperBaseEnglish, whisperSmall, whisperLargeTurbo,
    ]

    /// Small, fast and multilingual — the balance dictation wants, where a
    /// batch has to come back before the user has finished their next sentence.
    static let defaultModel = whisperBase

    static func model(id: String) -> TranscriptionModel? {
        all.first { $0.id == id }
    }

    /// The catalogue as the pane draws it: engines in a fixed order, each with
    /// its models, and no heading for an engine that offers nothing.
    static func grouped(_ models: [TranscriptionModel] = all) -> [(engine: TranscriptionEngineKind, models: [TranscriptionModel])] {
        TranscriptionEngineKind.allCases.compactMap { engine in
            let inEngine = models.filter { $0.engine == engine }
            return inEngine.isEmpty ? nil : (engine, inEngine)
        }
    }
}
