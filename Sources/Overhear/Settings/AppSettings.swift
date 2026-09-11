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
    private let listeningHotkeyKey = "listeningHotkey"
    private let listeningModeKey = "listeningMode"
    private let cancelWordKey = "cancelWord"
    private let stripAnnotationsKey = "stripTranscriptionAnnotations"
    private let translateUnsupportedKey = "translateUnsupportedLanguages"
    private let spaceInsertedTextKey = "addSpacesAroundInsertedText"

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

    /// The combination that starts and stops listening from any app, or none.
    ///
    /// Nothing on a fresh install, deliberately: any combination shipped as a
    /// default might already belong to the app the user is typing in, and a
    /// hotkey in the way is worse than one they have to record.
    ///
    /// Applies live, like `showOverlay`. Changing it re-registers the tap and
    /// reloads nothing.
    @Published var listeningHotkey: ListeningHotkey? {
        didSet {
            if let listeningHotkey {
                defaults.set(listeningHotkey.stored, forKey: listeningHotkeyKey)
            } else {
                defaults.removeObject(forKey: listeningHotkeyKey)
            }
        }
    }

    /// Whether the hotkey toggles listening or is held for the length of an
    /// utterance.
    ///
    /// Applies live and reloads nothing: the engine is built from the language
    /// set, the cancel word and the model, and this is none of them. What it
    /// does change is who ends a session, so `AppDelegate` stops whatever is
    /// running when it changes — the release ends only what a hold started,
    /// and hold to talk has no **Stop Listening** to reach a session with.
    @Published var listeningMode: ListeningMode {
        didSet {
            defaults.set(listeningMode.rawValue, forKey: listeningModeKey)
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

    /// Whether to separate what is pasted from what is already in the field —
    /// a space before it, and one after it as well when it lands mid-sentence.
    ///
    /// Applies live, like `stripAnnotations`: it is read on every insertion
    /// rather than baked into anything, so toggling it reloads nothing.
    @Published var spaceInsertedText: Bool {
        didSet {
            defaults.set(spaceInsertedText, forKey: spaceInsertedTextKey)
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
        if defaults.object(forKey: spaceInsertedTextKey) != nil {
            spaceInsertedText = defaults.bool(forKey: spaceInsertedTextKey)
        } else {
            spaceInsertedText = true
        }
        translateUnsupported = defaults.bool(forKey: translateUnsupportedKey)
        listeningHotkey = defaults.dictionary(forKey: listeningHotkeyKey)
            .flatMap(ListeningHotkey.init(stored:))
        listeningMode = defaults.string(forKey: listeningModeKey)
            .flatMap(ListeningMode.init(rawValue:)) ?? .alwaysOn
        activeModelID = defaults.string(forKey: activeModelKey) ?? ModelCatalog.defaultModel.id
        cancelWord = HotWord.defaultWord
        if let saved = defaults.string(forKey: cancelWordKey) {
            let candidates = availableHotWords ?? HotWordService.shared.allHotWords
            cancelWord = candidates.first { $0.modelValue == saved } ?? HotWord.defaultWord
        }
    }
}
