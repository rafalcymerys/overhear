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

/// Every model Overhear can run, in the order the pane lists them.
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

    /// NVIDIA's transducer model, English only. Faster than Whisper at
    /// comparable accuracy on English, and unable to transcribe anything else.
    static let parakeetV2 = TranscriptionModel(
        id: "parakeet-tdt-0.6b-v2",
        engine: .parakeet,
        name: "TDT 0.6B v2",
        variant: ParakeetVariant.v2.variant,
        downloadSize: 452 * 1_000_000,
        languageCodes: ["en"],
        note: nil
    )

    /// The multilingual build of the same model.
    ///
    /// The languages are the twenty-four the model was trained on that Overhear
    /// also lists — not FluidAudio's `Language`, which is a script classifier
    /// for the decode hint and names several the model never saw. Claiming one
    /// of those would put a language in the picker that comes back as noise,
    /// which is R-98 in a new engine. The twenty-fifth, Maltese, is missing from
    /// `RecognitionLanguage.all` rather than from the model.
    static let parakeetV3 = TranscriptionModel(
        id: "parakeet-tdt-0.6b-v3",
        engine: .parakeet,
        name: "TDT 0.6B v3",
        variant: ParakeetVariant.v3.variant,
        downloadSize: 470 * 1_000_000,
        languageCodes: [
            "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "hr", "hu",
            "it", "lt", "lv", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "uk",
        ],
        note: nil
    )

    private static let whisperModels: [TranscriptionModel] = [
        whisperTiny, whisperBase, whisperBaseEnglish, whisperSmall, whisperLargeTurbo,
    ]

    private static let parakeetModels: [TranscriptionModel] = [parakeetV2, parakeetV3]

    /// Parakeet's weights are compiled for the Neural Engine and its loader
    /// refuses anything else, so on an Intel Mac the models are not offered at
    /// all rather than offered and then failing after half a gigabyte. The
    /// group disappears with them — `grouped(_:)` drops an engine with nothing
    /// in it.
    #if arch(arm64)
    static let all: [TranscriptionModel] = whisperModels + parakeetModels
    #else
    static let all: [TranscriptionModel] = whisperModels
    #endif

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
