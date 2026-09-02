import Foundation

/// Fetches the wake word models the engine needs.
///
/// The four built-in words are downloaded rather than shipped in the bundle on
/// purpose. openWakeWord's pre-trained words are CC BY-NC-SA licensed — only
/// the two shared feature models are Apache 2.0 — so bundling them would attach
/// those terms to a distribution of Overhear itself. Fetching them at first
/// launch from openWakeWord's own release assets keeps this app's MIT terms
/// unencumbered.
@MainActor
final class WakeWordSetup: ObservableObject {
    /// openWakeWord's official release assets. The repo publishes `.tflite` and
    /// `.onnx` side by side under the same tag.
    static let releaseBase = "https://github.com/dscripka/openWakeWord/releases/download/v0.5.1"

    /// Local filename to the release asset it is fetched from.
    ///
    /// The word models are published with a version suffix but stored without
    /// one, because a filename is not private here: `HotWordService` derives a
    /// hot word's display name from it, so `alexa_v0.1.onnx` would reach
    /// Settings as "Alexa V0.1". Storing them as `alexa.onnx` also means
    /// `HotWord.modelPath` can derive the file from the word's own name instead
    /// of keeping a second table in step with this one.
    static let modelAssets: [String: String] = [
        // Needed whatever the chosen cancel word is: every word head runs on
        // top of these two.
        "melspectrogram.onnx": "melspectrogram.onnx",
        "embedding_model.onnx": "embedding_model.onnx",
        // The words offered in Settings.
        "alexa.onnx": "alexa_v0.1.onnx",
        "hey_jarvis.onnx": "hey_jarvis_v0.1.onnx",
        "hey_mycroft.onnx": "hey_mycroft_v0.1.onnx",
        "hey_rhasspy.onnx": "hey_rhasspy_v0.1.onnx",
    ]

    /// Every file setup is responsible for. `HotWordService` uses this to tell
    /// the models it manages apart from the ones a user installed.
    static let requiredFiles: [String] = modelAssets.keys.sorted()

    enum SetupError: LocalizedError {
        case downloadFailed(file: String, underlying: String)

        var errorDescription: String? {
            switch self {
            case let .downloadFailed(file, underlying):
                return "Could not download \(file): \(underlying)"
            }
        }
    }

    @Published private(set) var step: String = ""
    @Published private(set) var isWorking = false
    @Published private(set) var failure: String?

    private let directory: URL
    private let fetch: @Sendable (URL) async throws -> URL

    /// - Parameters:
    ///   - directory: where models are kept. Defaults to the same directory
    ///     `HotWordService` installs custom words into, so built-in and custom
    ///     models live together and are found the same way.
    ///   - fetch: how to pull a file down. Injected so tests never hit the network.
    init(directory: URL = HotWord.modelsDirectory,
         fetch: @escaping @Sendable (URL) async throws -> URL = WakeWordSetup.defaultFetch) {
        self.directory = directory
        self.fetch = fetch
    }

    /// Which required models are not on disk yet.
    static func missingFiles(in directory: URL) -> [String] {
        requiredFiles.filter {
            !FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    var isComplete: Bool { Self.missingFiles(in: directory).isEmpty }

    /// Download whatever is missing. Returns immediately when everything is
    /// already there, which is every launch after the first.
    func ensureModels() async throws {
        let missing = Self.missingFiles(in: directory)
        guard !missing.isEmpty else { return }

        isWorking = true
        failure = nil
        defer { isWorking = false }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, file) in missing.enumerated() {
            step = "Downloading wake word models (\(index + 1) of \(missing.count))…"
            guard let asset = Self.modelAssets[file],
                  let url = URL(string: "\(Self.releaseBase)/\(asset)") else {
                continue
            }
            do {
                let temporary = try await fetch(url)
                let destination = directory.appendingPathComponent(file)
                // Move into place only once the bytes are down, so an
                // interrupted download can't leave a truncated model that
                // would then look present on the next launch.
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporary, to: destination)
            } catch {
                let failure = SetupError.downloadFailed(file: file, underlying: error.localizedDescription)
                self.failure = failure.localizedDescription
                throw failure
            }
        }

        step = ""
    }

    nonisolated static let defaultFetch: @Sendable (URL) async throws -> URL = { url in
        let (temporary, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return temporary
    }
}
