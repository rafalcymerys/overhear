import Foundation

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
