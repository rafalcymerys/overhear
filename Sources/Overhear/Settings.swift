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
