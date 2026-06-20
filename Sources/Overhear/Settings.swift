import Foundation

struct WhisperLanguage: Identifiable, Hashable, Codable {
    let code: String
    let name: String
    var id: String { code }

    static let all: [WhisperLanguage] = [
        WhisperLanguage(code: "af", name: "Afrikaans"),
        WhisperLanguage(code: "ar", name: "Arabic"),
        WhisperLanguage(code: "hy", name: "Armenian"),
        WhisperLanguage(code: "az", name: "Azerbaijani"),
        WhisperLanguage(code: "be", name: "Belarusian"),
        WhisperLanguage(code: "bs", name: "Bosnian"),
        WhisperLanguage(code: "bg", name: "Bulgarian"),
        WhisperLanguage(code: "ca", name: "Catalan"),
        WhisperLanguage(code: "zh", name: "Chinese"),
        WhisperLanguage(code: "hr", name: "Croatian"),
        WhisperLanguage(code: "cs", name: "Czech"),
        WhisperLanguage(code: "da", name: "Danish"),
        WhisperLanguage(code: "nl", name: "Dutch"),
        WhisperLanguage(code: "en", name: "English"),
        WhisperLanguage(code: "et", name: "Estonian"),
        WhisperLanguage(code: "fi", name: "Finnish"),
        WhisperLanguage(code: "fr", name: "French"),
        WhisperLanguage(code: "gl", name: "Galician"),
        WhisperLanguage(code: "de", name: "German"),
        WhisperLanguage(code: "el", name: "Greek"),
        WhisperLanguage(code: "he", name: "Hebrew"),
        WhisperLanguage(code: "hi", name: "Hindi"),
        WhisperLanguage(code: "hu", name: "Hungarian"),
        WhisperLanguage(code: "is", name: "Icelandic"),
        WhisperLanguage(code: "id", name: "Indonesian"),
        WhisperLanguage(code: "it", name: "Italian"),
        WhisperLanguage(code: "ja", name: "Japanese"),
        WhisperLanguage(code: "kk", name: "Kazakh"),
        WhisperLanguage(code: "ko", name: "Korean"),
        WhisperLanguage(code: "lv", name: "Latvian"),
        WhisperLanguage(code: "lt", name: "Lithuanian"),
        WhisperLanguage(code: "mk", name: "Macedonian"),
        WhisperLanguage(code: "ms", name: "Malay"),
        WhisperLanguage(code: "mr", name: "Marathi"),
        WhisperLanguage(code: "mi", name: "Maori"),
        WhisperLanguage(code: "ne", name: "Nepali"),
        WhisperLanguage(code: "no", name: "Norwegian"),
        WhisperLanguage(code: "fa", name: "Persian"),
        WhisperLanguage(code: "pl", name: "Polish"),
        WhisperLanguage(code: "pt", name: "Portuguese"),
        WhisperLanguage(code: "ro", name: "Romanian"),
        WhisperLanguage(code: "ru", name: "Russian"),
        WhisperLanguage(code: "sr", name: "Serbian"),
        WhisperLanguage(code: "sk", name: "Slovak"),
        WhisperLanguage(code: "sl", name: "Slovenian"),
        WhisperLanguage(code: "es", name: "Spanish"),
        WhisperLanguage(code: "sw", name: "Swahili"),
        WhisperLanguage(code: "sv", name: "Swedish"),
        WhisperLanguage(code: "tl", name: "Tagalog"),
        WhisperLanguage(code: "ta", name: "Tamil"),
        WhisperLanguage(code: "th", name: "Thai"),
        WhisperLanguage(code: "tr", name: "Turkish"),
        WhisperLanguage(code: "uk", name: "Ukrainian"),
        WhisperLanguage(code: "ur", name: "Urdu"),
        WhisperLanguage(code: "vi", name: "Vietnamese"),
        WhisperLanguage(code: "cy", name: "Welsh"),
    ]
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let languagesKey = "selectedLanguages"
    private let overlayKey = "showOverlay"

    @Published var selectedLanguageCodes: Set<String> {
        didSet {
            let array = Array(selectedLanguageCodes)
            UserDefaults.standard.set(array, forKey: languagesKey)
        }
    }

    @Published var showOverlay: Bool {
        didSet {
            UserDefaults.standard.set(showOverlay, forKey: overlayKey)
        }
    }

    var selectedLanguages: [WhisperLanguage] {
        WhisperLanguage.all.filter { selectedLanguageCodes.contains($0.code) }
    }

    private init() {
        if let saved = UserDefaults.standard.stringArray(forKey: languagesKey) {
            selectedLanguageCodes = Set(saved)
        } else {
            selectedLanguageCodes = ["en", "pl"]
        }
        if UserDefaults.standard.object(forKey: overlayKey) != nil {
            showOverlay = UserDefaults.standard.bool(forKey: overlayKey)
        } else {
            showOverlay = true
        }
    }
}
