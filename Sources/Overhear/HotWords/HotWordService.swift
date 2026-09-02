import AppKit
import Foundation

@MainActor
final class HotWordService: ObservableObject {
    static let shared = HotWordService()

    /// Fetches a remote model to a local temporary file.
    typealias Downloader = (URL, @escaping @Sendable (Result<URL, Error>) -> Void) -> Void

    @Published var customHotWords: [HotWord] = []
    @Published var isDownloading = false
    @Published var downloadError: String?

    private let modelsDirectory: URL
    private let download: Downloader

    var allHotWords: [HotWord] {
        HotWord.builtIn + customHotWords
    }

    /// - Parameters:
    ///   - modelsDirectory: where installed `.onnx` models live.
    ///   - download: how to fetch a remote model. Injected so tests never hit
    ///     the network.
    init(modelsDirectory: URL = HotWord.modelsDirectory,
         download: @escaping Downloader = HotWordService.urlSessionDownload) {
        self.modelsDirectory = modelsDirectory
        self.download = download
        reload()
    }

    func reload() {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: modelsDirectory.path) else {
            customHotWords = []
            return
        }
        customHotWords = files
            // The built-in words and the shared feature models live in this
            // same directory, and they are not the user's to see or delete —
            // listing them would offer "Melspectrogram" as a cancel word and
            // put a trash button next to a file every word depends on.
            .filter { $0.hasSuffix(".onnx") && !WakeWordSetup.requiredFiles.contains($0) }
            .sorted()
            .map { filename in
                let path = modelsDirectory.appendingPathComponent(filename).path
                let name = filename
                    .replacingOccurrences(of: ".onnx", with: "")
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .capitalized
                return HotWord.custom(path: path, name: name)
            }
    }

    func remove(_ word: HotWord, settings: AppSettings? = nil) {
        let settings = settings ?? .shared
        if settings.cancelWord == word {
            settings.cancelWord = HotWord.defaultWord
        }
        try? FileManager.default.removeItem(atPath: word.modelValue)
        reload()
    }

    /// Copy a local model into the models directory, replacing any existing file
    /// of the same name.
    @discardableResult
    func install(from sourceURL: URL) -> Bool {
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let destURL = modelsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            reload()
            return true
        } catch {
            downloadError = error.localizedDescription
            return false
        }
    }

    func installFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "onnx")!]
        panel.allowsMultipleSelection = false
        panel.message = "Select an openwakeword .onnx model file"
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        install(from: sourceURL)
    }

    func downloadFromURL(_ urlString: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString), url.scheme != nil, url.host != nil else {
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

        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        download(url) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isDownloading = false
                switch result {
                case .failure(let error):
                    self.downloadError = error.localizedDescription
                    completion(false)
                case .success(let tempURL):
                    let destURL = self.modelsDirectory.appendingPathComponent(url.lastPathComponent)
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
            }
        }
    }

    nonisolated static func urlSessionDownload(_ url: URL,
                                               completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            if let error {
                completion(.failure(error))
            } else if let tempURL {
                completion(.success(tempURL))
            } else {
                completion(.failure(URLError(.badServerResponse)))
            }
        }.resume()
    }
}
