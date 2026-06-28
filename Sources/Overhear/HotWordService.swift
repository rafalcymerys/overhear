import AppKit
import Foundation

@MainActor
final class HotWordService: ObservableObject {
    static let shared = HotWordService()

    @Published var customHotWords: [HotWord] = []
    @Published var isDownloading = false
    @Published var downloadError: String?

    var allHotWords: [HotWord] {
        HotWord.builtIn + customHotWords
    }

    private init() {
        reload()
    }

    func reload() {
        let dir = HotWord.modelsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            customHotWords = []
            return
        }
        customHotWords = files
            .filter { $0.hasSuffix(".onnx") }
            .sorted()
            .map { filename in
                let path = dir.appendingPathComponent(filename).path
                let name = filename
                    .replacingOccurrences(of: ".onnx", with: "")
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .capitalized
                return HotWord.custom(path: path, name: name)
            }
    }

    func remove(_ word: HotWord) {
        if AppSettings.shared.cancelWord == word {
            AppSettings.shared.cancelWord = HotWord.defaultWord
        }
        try? FileManager.default.removeItem(atPath: word.modelValue)
        reload()
    }

    func installFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "onnx")!]
        panel.allowsMultipleSelection = false
        panel.message = "Select an openwakeword .onnx model file"
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        let modelsDir = HotWord.modelsDirectory
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        let filename = sourceURL.lastPathComponent
        let destURL = modelsDir.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            reload()
        } catch {
            downloadError = error.localizedDescription
        }
    }

    func downloadFromURL(_ urlString: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else {
            downloadError = "Invalid URL"
            completion(false)
            return
        }
        guard url.pathExtension.lowercased() == "onnx" else {
            downloadError = "URL must point to an .onnx file"
            completion(false)
            return
        }
        isDownloading = true
        downloadError = nil

        let modelsDir = HotWord.modelsDirectory
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isDownloading = false
                if let error {
                    self.downloadError = error.localizedDescription
                    completion(false)
                    return
                }
                guard let tempURL else {
                    self.downloadError = "Download failed"
                    completion(false)
                    return
                }
                let filename = url.lastPathComponent
                let destURL = modelsDir.appendingPathComponent(filename)
                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destURL)
                    self.reload()
                    completion(true)
                } catch {
                    self.downloadError = error.localizedDescription
                    completion(false)
                }
            }
        }.resume()
    }
}
