import Foundation

/// A word that can be spoken to cancel the batch being dictated.
///
/// Four are built in and downloaded on first launch; the rest are `.onnx`
/// models the user installs. `modelValue` is a bare name for a built-in word
/// and an absolute path for a custom one, which is what `modelPath(in:)`
/// resolves.
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
