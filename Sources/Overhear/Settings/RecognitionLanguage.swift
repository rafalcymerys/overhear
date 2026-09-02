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
