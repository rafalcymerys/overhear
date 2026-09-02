import Foundation

/// A language the app can be asked to recognise.
///
/// Named for the job rather than for an engine: the same list is offered
/// whichever model is active, and each model narrows it to what it supports.
struct RecognitionLanguage: Identifiable, Hashable, Codable {
    let code: String
    let name: String
    let flag: String
    var id: String { code }

    static let all: [RecognitionLanguage] = [
        RecognitionLanguage(code: "af", name: "Afrikaans", flag: "🇿🇦"),
        RecognitionLanguage(code: "ar", name: "Arabic", flag: "🇸🇦"),
        RecognitionLanguage(code: "hy", name: "Armenian", flag: "🇦🇲"),
        RecognitionLanguage(code: "az", name: "Azerbaijani", flag: "🇦🇿"),
        RecognitionLanguage(code: "be", name: "Belarusian", flag: "🇧🇾"),
        RecognitionLanguage(code: "bs", name: "Bosnian", flag: "🇧🇦"),
        RecognitionLanguage(code: "bg", name: "Bulgarian", flag: "🇧🇬"),
        RecognitionLanguage(code: "ca", name: "Catalan", flag: "🇪🇸"),
        RecognitionLanguage(code: "zh", name: "Chinese", flag: "🇨🇳"),
        RecognitionLanguage(code: "hr", name: "Croatian", flag: "🇭🇷"),
        RecognitionLanguage(code: "cs", name: "Czech", flag: "🇨🇿"),
        RecognitionLanguage(code: "da", name: "Danish", flag: "🇩🇰"),
        RecognitionLanguage(code: "nl", name: "Dutch", flag: "🇳🇱"),
        RecognitionLanguage(code: "en", name: "English", flag: "🇨🇦"),
        RecognitionLanguage(code: "et", name: "Estonian", flag: "🇪🇪"),
        RecognitionLanguage(code: "fi", name: "Finnish", flag: "🇫🇮"),
        RecognitionLanguage(code: "fr", name: "French", flag: "🇫🇷"),
        RecognitionLanguage(code: "gl", name: "Galician", flag: "🇪🇸"),
        RecognitionLanguage(code: "de", name: "German", flag: "🇩🇪"),
        RecognitionLanguage(code: "el", name: "Greek", flag: "🇬🇷"),
        RecognitionLanguage(code: "he", name: "Hebrew", flag: "🇮🇱"),
        RecognitionLanguage(code: "hi", name: "Hindi", flag: "🇮🇳"),
        RecognitionLanguage(code: "hu", name: "Hungarian", flag: "🇭🇺"),
        RecognitionLanguage(code: "is", name: "Icelandic", flag: "🇮🇸"),
        RecognitionLanguage(code: "id", name: "Indonesian", flag: "🇮🇩"),
        RecognitionLanguage(code: "it", name: "Italian", flag: "🇮🇹"),
        RecognitionLanguage(code: "ja", name: "Japanese", flag: "🇯🇵"),
        RecognitionLanguage(code: "kk", name: "Kazakh", flag: "🇰🇿"),
        RecognitionLanguage(code: "ko", name: "Korean", flag: "🇰🇷"),
        RecognitionLanguage(code: "lv", name: "Latvian", flag: "🇱🇻"),
        RecognitionLanguage(code: "lt", name: "Lithuanian", flag: "🇱🇹"),
        RecognitionLanguage(code: "mk", name: "Macedonian", flag: "🇲🇰"),
        RecognitionLanguage(code: "ms", name: "Malay", flag: "🇲🇾"),
        RecognitionLanguage(code: "mr", name: "Marathi", flag: "🇮🇳"),
        RecognitionLanguage(code: "mi", name: "Maori", flag: "🇳🇿"),
        RecognitionLanguage(code: "ne", name: "Nepali", flag: "🇳🇵"),
        RecognitionLanguage(code: "no", name: "Norwegian", flag: "🇳🇴"),
        RecognitionLanguage(code: "fa", name: "Persian", flag: "🇮🇷"),
        RecognitionLanguage(code: "pl", name: "Polish", flag: "🇵🇱"),
        RecognitionLanguage(code: "pt", name: "Portuguese", flag: "🇵🇹"),
        RecognitionLanguage(code: "ro", name: "Romanian", flag: "🇷🇴"),
        RecognitionLanguage(code: "ru", name: "Russian", flag: "🇷🇺"),
        RecognitionLanguage(code: "sr", name: "Serbian", flag: "🇷🇸"),
        RecognitionLanguage(code: "sk", name: "Slovak", flag: "🇸🇰"),
        RecognitionLanguage(code: "sl", name: "Slovenian", flag: "🇸🇮"),
        RecognitionLanguage(code: "es", name: "Spanish", flag: "🇪🇸"),
        RecognitionLanguage(code: "sw", name: "Swahili", flag: "🇰🇪"),
        RecognitionLanguage(code: "sv", name: "Swedish", flag: "🇸🇪"),
        RecognitionLanguage(code: "tl", name: "Tagalog", flag: "🇵🇭"),
        RecognitionLanguage(code: "ta", name: "Tamil", flag: "🇮🇳"),
        RecognitionLanguage(code: "th", name: "Thai", flag: "🇹🇭"),
        RecognitionLanguage(code: "tr", name: "Turkish", flag: "🇹🇷"),
        RecognitionLanguage(code: "uk", name: "Ukrainian", flag: "🇺🇦"),
        RecognitionLanguage(code: "ur", name: "Urdu", flag: "🇵🇰"),
        RecognitionLanguage(code: "vi", name: "Vietnamese", flag: "🇻🇳"),
        RecognitionLanguage(code: "cy", name: "Welsh", flag: "🏴󠁧󠁢󠁷󠁬󠁳󠁿"),
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

    var selectedLanguages: [RecognitionLanguage] {
        RecognitionLanguage.all.filter { selectedLanguageCodes.contains($0.code) }
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
    var unsupportedSelectedLanguages: [RecognitionLanguage] {
        RecognitionLanguage.all.filter {
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
