import Foundation

/// Fetches the wake word models the engine needs.
///
/// A step in the setup window rather than something that happens behind it:
/// `SetupCoordinator` owns one of these, draws its progress on a card, and
/// does not call setup finished until `isComplete`.
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

    /// What the card says under its progress bar while files are arriving.
    @Published private(set) var step: String = ""
    @Published private(set) var isWorking = false
    @Published private(set) var failure: String?

    /// Whether every required model is on disk. Stored rather than asked of
    /// the disk each time, because the setup window has to be told the moment
    /// it becomes true — it is one of the four things it is waiting on.
    @Published private(set) var isComplete: Bool

    /// How much of this run has arrived, or nothing when nothing is running.
    ///
    /// Counted in files rather than bytes: the fetch hands back a file that is
    /// already finished and says nothing on the way, so a sixth of the bar is
    /// the finest this can honestly draw. It is a fraction of what *this* run
    /// has to fetch, so a launch missing one model fills the bar with that one.
    @Published private(set) var progress: Double?

    private let directory: URL
    private let fetch: @Sendable (URL) async throws -> URL
    private var downloadTask: Task<Void, Never>?

    /// - Parameters:
    ///   - directory: where models are kept. Defaults to the same directory
    ///     `HotWordService` installs custom words into, so built-in and custom
    ///     models live together and are found the same way.
    ///   - fetch: how to pull a file down. Injected so tests never hit the network.
    init(directory: URL = HotWord.modelsDirectory,
         fetch: @escaping @Sendable (URL) async throws -> URL = WakeWordSetup.defaultFetch) {
        self.directory = directory
        self.fetch = fetch
        self.isComplete = Self.missingFiles(in: directory).isEmpty
    }

    /// Which required models are not on disk yet.
    static func missingFiles(in directory: URL) -> [String] {
        requiredFiles.filter {
            !FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    /// Re-read the disk. The setup window can be reopened long after a model
    /// was deleted from under it.
    func refresh() {
        isComplete = Self.missingFiles(in: directory).isEmpty
    }

    /// Start fetching whatever is missing, unless something already is or the
    /// last attempt failed — a failure waits for `retry()`, so that reopening
    /// the window or the menu does not quietly start the download over.
    ///
    /// The card has no button to press: there is nothing to choose here, so
    /// this is called as soon as the window has a card to draw.
    func startDownload() {
        guard downloadTask == nil, failure == nil, !isComplete else { return }
        downloadTask = Task { [weak self] in
            try? await self?.ensureModels()
            self?.downloadTask = nil
        }
    }

    /// What **Try Again** does: forget the failure that stopped `startDownload`
    /// and pick up from the files still missing.
    func retry() {
        failure = nil
        startDownload()
    }

    /// Download whatever is missing. Returns immediately when everything is
    /// already there, which is every launch after the first.
    func ensureModels() async throws {
        let missing = Self.missingFiles(in: directory)
        guard !missing.isEmpty else { return }

        isWorking = true
        failure = nil
        progress = 0
        defer {
            isWorking = false
            progress = nil
            refresh()
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, file) in missing.enumerated() {
            step = "Downloading · \(index + 1) of \(missing.count)"
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
                progress = Double(index + 1) / Double(missing.count)
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
