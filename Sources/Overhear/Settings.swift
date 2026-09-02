import Foundation

struct WhisperLanguage: Identifiable, Hashable, Codable {
    let code: String
    let name: String
    let flag: String
    var id: String { code }

    static let all: [WhisperLanguage] = [
        WhisperLanguage(code: "af", name: "Afrikaans", flag: "🇿🇦"),
        WhisperLanguage(code: "ar", name: "Arabic", flag: "🇸🇦"),
        WhisperLanguage(code: "hy", name: "Armenian", flag: "🇦🇲"),
        WhisperLanguage(code: "az", name: "Azerbaijani", flag: "🇦🇿"),
        WhisperLanguage(code: "be", name: "Belarusian", flag: "🇧🇾"),
        WhisperLanguage(code: "bs", name: "Bosnian", flag: "🇧🇦"),
        WhisperLanguage(code: "bg", name: "Bulgarian", flag: "🇧🇬"),
        WhisperLanguage(code: "ca", name: "Catalan", flag: "🇪🇸"),
        WhisperLanguage(code: "zh", name: "Chinese", flag: "🇨🇳"),
        WhisperLanguage(code: "hr", name: "Croatian", flag: "🇭🇷"),
        WhisperLanguage(code: "cs", name: "Czech", flag: "🇨🇿"),
        WhisperLanguage(code: "da", name: "Danish", flag: "🇩🇰"),
        WhisperLanguage(code: "nl", name: "Dutch", flag: "🇳🇱"),
        WhisperLanguage(code: "en", name: "English", flag: "🇨🇦"),
        WhisperLanguage(code: "et", name: "Estonian", flag: "🇪🇪"),
        WhisperLanguage(code: "fi", name: "Finnish", flag: "🇫🇮"),
        WhisperLanguage(code: "fr", name: "French", flag: "🇫🇷"),
        WhisperLanguage(code: "gl", name: "Galician", flag: "🇪🇸"),
        WhisperLanguage(code: "de", name: "German", flag: "🇩🇪"),
        WhisperLanguage(code: "el", name: "Greek", flag: "🇬🇷"),
        WhisperLanguage(code: "he", name: "Hebrew", flag: "🇮🇱"),
        WhisperLanguage(code: "hi", name: "Hindi", flag: "🇮🇳"),
        WhisperLanguage(code: "hu", name: "Hungarian", flag: "🇭🇺"),
        WhisperLanguage(code: "is", name: "Icelandic", flag: "🇮🇸"),
        WhisperLanguage(code: "id", name: "Indonesian", flag: "🇮🇩"),
        WhisperLanguage(code: "it", name: "Italian", flag: "🇮🇹"),
        WhisperLanguage(code: "ja", name: "Japanese", flag: "🇯🇵"),
        WhisperLanguage(code: "kk", name: "Kazakh", flag: "🇰🇿"),
        WhisperLanguage(code: "ko", name: "Korean", flag: "🇰🇷"),
        WhisperLanguage(code: "lv", name: "Latvian", flag: "🇱🇻"),
        WhisperLanguage(code: "lt", name: "Lithuanian", flag: "🇱🇹"),
        WhisperLanguage(code: "mk", name: "Macedonian", flag: "🇲🇰"),
        WhisperLanguage(code: "ms", name: "Malay", flag: "🇲🇾"),
        WhisperLanguage(code: "mr", name: "Marathi", flag: "🇮🇳"),
        WhisperLanguage(code: "mi", name: "Maori", flag: "🇳🇿"),
        WhisperLanguage(code: "ne", name: "Nepali", flag: "🇳🇵"),
        WhisperLanguage(code: "no", name: "Norwegian", flag: "🇳🇴"),
        WhisperLanguage(code: "fa", name: "Persian", flag: "🇮🇷"),
        WhisperLanguage(code: "pl", name: "Polish", flag: "🇵🇱"),
        WhisperLanguage(code: "pt", name: "Portuguese", flag: "🇵🇹"),
        WhisperLanguage(code: "ro", name: "Romanian", flag: "🇷🇴"),
        WhisperLanguage(code: "ru", name: "Russian", flag: "🇷🇺"),
        WhisperLanguage(code: "sr", name: "Serbian", flag: "🇷🇸"),
        WhisperLanguage(code: "sk", name: "Slovak", flag: "🇸🇰"),
        WhisperLanguage(code: "sl", name: "Slovenian", flag: "🇸🇮"),
        WhisperLanguage(code: "es", name: "Spanish", flag: "🇪🇸"),
        WhisperLanguage(code: "sw", name: "Swahili", flag: "🇰🇪"),
        WhisperLanguage(code: "sv", name: "Swedish", flag: "🇸🇪"),
        WhisperLanguage(code: "tl", name: "Tagalog", flag: "🇵🇭"),
        WhisperLanguage(code: "ta", name: "Tamil", flag: "🇮🇳"),
        WhisperLanguage(code: "th", name: "Thai", flag: "🇹🇭"),
        WhisperLanguage(code: "tr", name: "Turkish", flag: "🇹🇷"),
        WhisperLanguage(code: "uk", name: "Ukrainian", flag: "🇺🇦"),
        WhisperLanguage(code: "ur", name: "Urdu", flag: "🇵🇰"),
        WhisperLanguage(code: "vi", name: "Vietnamese", flag: "🇻🇳"),
        WhisperLanguage(code: "cy", name: "Welsh", flag: "🏴󠁧󠁢󠁷󠁬󠁳󠁿"),
    ]
}

struct HotWord: Hashable, Identifiable {
    let modelValue: String
    let displayName: String
    let isCustom: Bool

    var id: String { modelValue }

    static let builtIn: [HotWord] = [
        HotWord(modelValue: "alexa", displayName: "Alexa", isCustom: false),
        HotWord(modelValue: "hey_jarvis", displayName: "Hey Jarvis", isCustom: false),
        HotWord(modelValue: "hey_mycroft", displayName: "Hey Mycroft", isCustom: false),
        HotWord(modelValue: "hey_rhasspy", displayName: "Hey Rhasspy", isCustom: false),
    ]

    static let defaultWord = builtIn[0]

    static func custom(path: String, name: String) -> HotWord {
        HotWord(modelValue: path, displayName: name, isCustom: true)
    }

    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Overhear/models")
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let defaultLanguageCodes: Set<String> = ["en", "pl"]

    private let languagesKey = "selectedLanguages"
    private let activeModelKey = "activeTranscriptionModel"
    private let overlayKey = "showOverlay"
    private let dictateOnLaunchKey = "dictateOnLaunch"
    private let cancelWordKey = "cancelWord"
    private let stripAnnotationsKey = "stripTranscriptionAnnotations"
    private let translateUnsupportedKey = "translateUnsupportedLanguages"

    private let defaults: UserDefaults

    @Published var selectedLanguageCodes: Set<String> {
        didSet {
            let array = Array(selectedLanguageCodes)
            defaults.set(array, forKey: languagesKey)
        }
    }

    /// Which model transcribes. Stored by id rather than by variant so the
    /// stored value survives a variant being renamed under it.
    @Published var activeModelID: String {
        didSet {
            defaults.set(activeModelID, forKey: activeModelKey)
        }
    }

    @Published var showOverlay: Bool {
        didSet {
            defaults.set(showOverlay, forKey: overlayKey)
        }
    }

    @Published var dictateOnLaunch: Bool {
        didSet {
            defaults.set(dictateOnLaunch, forKey: dictateOnLaunchKey)
        }
    }

    @Published var cancelWord: HotWord {
        didSet {
            defaults.set(cancelWord.modelValue, forKey: cancelWordKey)
        }
    }

    /// Whether to drop Whisper's parenthesised descriptions of non-speech —
    /// `(coughing)` and the like — instead of pasting them.
    ///
    /// Unlike the language set and the cancel word, this one applies live: it
    /// is read on every transcription rather than baked into the engine, so
    /// toggling it does not reload any models.
    @Published var stripAnnotations: Bool {
        didSet {
            defaults.set(stripAnnotations, forKey: stripAnnotationsKey)
        }
    }

    /// Whether speech in a language the user did not select is translated to
    /// English. A selected language is never translated, whatever this says.
    ///
    /// Off by default — the point of the setting is to make translation a
    /// choice rather than something that happens by accident.
    @Published var translateUnsupported: Bool {
        didSet {
            defaults.set(translateUnsupported, forKey: translateUnsupportedKey)
        }
    }

    var selectedLanguages: [WhisperLanguage] {
        WhisperLanguage.all.filter { selectedLanguageCodes.contains($0.code) }
    }

    var activeModel: TranscriptionModel {
        ModelCatalog.model(id: activeModelID) ?? ModelCatalog.defaultModel
    }

    /// The languages the engine is actually given: the user's selection,
    /// narrowed to what the active model can transcribe.
    ///
    /// The selection itself is never narrowed. A model that cannot do Polish
    /// makes Polish inert, not forgotten — activating a multilingual model
    /// again brings it back without the user reselecting it, which is the whole
    /// reason these are two properties rather than one.
    var effectiveLanguageCodes: Set<String> {
        let supported = selectedLanguageCodes.filter { activeModel.supports($0) }
        guard supported.isEmpty else { return supported }
        // Every selected language is unsupported, so fall back to what the
        // model does have rather than handing the engine nothing.
        return Set(activeModel.supportedLanguages.prefix(1).map(\.code))
    }

    /// Selected languages this model cannot transcribe. What the pane tells the
    /// user about after activating an English-only model.
    var unsupportedSelectedLanguages: [WhisperLanguage] {
        WhisperLanguage.all.filter {
            selectedLanguageCodes.contains($0.code) && !activeModel.supports($0.code)
        }
    }

    /// - Parameters:
    ///   - defaults: storage to read and write. Tests pass a throwaway suite.
    ///   - availableHotWords: the words a persisted cancel word can resolve
    ///     against. Defaults to whatever is installed.
    init(defaults: UserDefaults = .standard, availableHotWords: [HotWord]? = nil) {
        self.defaults = defaults

        if let saved = defaults.stringArray(forKey: languagesKey) {
            selectedLanguageCodes = Set(saved)
        } else {
            selectedLanguageCodes = Self.defaultLanguageCodes
        }
        if defaults.object(forKey: overlayKey) != nil {
            showOverlay = defaults.bool(forKey: overlayKey)
        } else {
            showOverlay = true
        }
        if defaults.object(forKey: dictateOnLaunchKey) != nil {
            dictateOnLaunch = defaults.bool(forKey: dictateOnLaunchKey)
        } else {
            dictateOnLaunch = true
        }
        if defaults.object(forKey: stripAnnotationsKey) != nil {
            stripAnnotations = defaults.bool(forKey: stripAnnotationsKey)
        } else {
            stripAnnotations = true
        }
        translateUnsupported = defaults.bool(forKey: translateUnsupportedKey)
        activeModelID = defaults.string(forKey: activeModelKey) ?? ModelCatalog.defaultModel.id
        cancelWord = HotWord.defaultWord
        if let saved = defaults.string(forKey: cancelWordKey) {
            let candidates = availableHotWords ?? HotWordService.shared.allHotWords
            cancelWord = candidates.first { $0.modelValue == saved } ?? HotWord.defaultWord
        }
    }
}
