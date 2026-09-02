import Foundation

/// Every preference the app keeps, backed by `UserDefaults`.
///
/// One published property per setting, so a view binds to it directly and
/// `AppDelegate` observes the two that need the engine rebuilt.
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
