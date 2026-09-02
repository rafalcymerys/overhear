import Foundation
import WhisperKit

/// Owns what is on disk: which models are downloaded, what a download is doing
/// right now, and how much space the lot takes.
///
/// The service never loads a model — activating one only writes the setting,
/// and `AppDelegate` reloads the engine off that. Keeping the two apart means a
/// download can run while dictation continues on the model already loaded.
@MainActor
final class TranscriptionModelService: ObservableObject {
    static let shared = TranscriptionModelService()

    /// Fetches one model, reporting progress from 0 to 1 as it goes.
    ///
    /// Injected so tests never reach the network — the real one is
    /// `WhisperKit.download`, which is also what would otherwise run
    /// unannounced inside `Transcriber.load()`.
    typealias Downloader = @Sendable (TranscriptionModel, URL, @escaping @Sendable (Double) -> Void) async throws -> Void

    @Published private(set) var downloadedIDs: Set<String> = []

    /// How far each running download has got, keyed by model id. A model with
    /// no entry is not downloading.
    @Published private(set) var progress: [String: Double] = [:]

    /// Why a download failed, keyed by model id. Cleared when it is retried.
    @Published private(set) var failures: [String: String] = [:]

    /// Bytes the downloaded models take, measured rather than added up from the
    /// catalogue's figures.
    @Published private(set) var diskUsage: Int64 = 0

    private let baseDirectory: URL
    private let download: Downloader
    private let settings: AppSettings
    private var tasks: [String: Task<Void, Never>] = [:]

    /// - Parameters:
    ///   - baseDirectory: where model weights are kept. Tests pass a temporary
    ///     directory.
    ///   - settings: where the active model is stored.
    ///   - download: how to fetch a model.
    init(baseDirectory: URL = TranscriptionModelService.defaultBaseDirectory,
         settings: AppSettings? = nil,
         download: @escaping Downloader = TranscriptionModelService.whisperKitDownload) {
        self.baseDirectory = baseDirectory
        self.settings = settings ?? .shared
        self.download = download
        refresh()
    }

    /// Where the weights live.
    ///
    /// WhisperKit defaults to `~/Documents/huggingface`, which is the wrong
    /// place for hundreds of megabytes a user never chose to store: Documents
    /// is theirs, it is backed up, and on a Mac with iCloud Drive enabled it is
    /// synced. Application Support is where a cache like this belongs.
    ///
    /// It gets its own subdirectory rather than sharing the wake word models
    /// one: WhisperKit creates a `models/<org>/<repo>` tree beneath whatever it
    /// is given, and `HotWordService` lists that same directory looking for the
    /// user's `.onnx` files.
    nonisolated static var defaultBaseDirectory: URL {
        HotWord.modelsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("whisper")
    }

    // MARK: - What is on disk

    /// The folder a model's weights land in.
    ///
    /// WhisperKit's `HubApi` lays the repository out beneath the download base,
    /// so this is where its snapshot ends up rather than a directory Overhear
    /// chose.
    func folder(for model: TranscriptionModel) -> URL {
        baseDirectory
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent("openai_whisper-\(model.variant)")
    }

    func isDownloaded(_ model: TranscriptionModel) -> Bool {
        downloadedIDs.contains(model.id)
    }

    /// What one model takes on disk, or what it is expected to take when it is
    /// not downloaded — the removal confirmation and the active model card both
    /// want a figure either way.
    func diskUsage(of model: TranscriptionModel) -> Int64 {
        isDownloaded(model) ? size(of: folder(for: model)) : model.downloadSize
    }

    func isDownloading(_ model: TranscriptionModel) -> Bool {
        progress[model.id] != nil
    }

    /// Re-read the disk. Called after anything that could have changed it, and
    /// on launch, where a model may have been deleted while Overhear was shut.
    func refresh() {
        downloadedIDs = Set(ModelCatalog.all.filter { hasFiles(for: $0) }.map(\.id))
        diskUsage = ModelCatalog.all
            .filter { downloadedIDs.contains($0.id) }
            .reduce(0) { $0 + size(of: folder(for: $1)) }
    }

    /// A folder counts as a downloaded model only when it holds a compiled
    /// model, which is what tells a finished download from the directory a
    /// cancelled one left behind.
    private func hasFiles(for model: TranscriptionModel) -> Bool {
        let folder = folder(for: model)
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return false
        }
        return contents.contains { $0.hasSuffix(".mlmodelc") }
    }

    private func size(of directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Downloading

    /// Fetch a model, or do nothing if it is already here or already running.
    func startDownload(_ model: TranscriptionModel) {
        guard !isDownloaded(model), tasks[model.id] == nil else { return }

        failures[model.id] = nil
        progress[model.id] = 0

        tasks[model.id] = Task { [weak self] in
            guard let self else { return }
            let destination = self.baseDirectory
            do {
                try await self.download(model, destination) { fraction in
                    Task { @MainActor [weak self] in
                        // A cancelled download can still report progress on its
                        // way out; it must not resurrect a row the user just
                        // sent back to "Download".
                        guard self?.tasks[model.id] != nil else { return }
                        self?.progress[model.id] = fraction
                    }
                }
                guard !Task.isCancelled else { return }
                self.finish(model)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.fail(model, with: error)
            }
        }
    }

    /// Stop a running download and leave nothing behind.
    ///
    /// The partial snapshot is deleted rather than kept as a resume point:
    /// nothing in the interface offers to resume, so a half-model on disk would
    /// only be a folder that looks like a model and cannot load.
    func cancelDownload(_ model: TranscriptionModel) {
        guard let task = tasks[model.id] else { return }
        task.cancel()
        tasks[model.id] = nil
        progress[model.id] = nil
        failures[model.id] = nil
        discardPartial(model)
        refresh()
    }

    private func finish(_ model: TranscriptionModel) {
        tasks[model.id] = nil
        progress[model.id] = nil
        failures[model.id] = nil
        refresh()
    }

    private func fail(_ model: TranscriptionModel, with error: Error) {
        tasks[model.id] = nil
        progress[model.id] = nil
        failures[model.id] = error.localizedDescription
        discardPartial(model)
        refresh()
    }

    private func discardPartial(_ model: TranscriptionModel) {
        guard !hasFiles(for: model) else { return }
        try? FileManager.default.removeItem(at: folder(for: model))
    }

    // MARK: - Activating and removing

    var activeModel: TranscriptionModel {
        settings.activeModel
    }

    func isActive(_ model: TranscriptionModel) -> Bool {
        settings.activeModelID == model.id
    }

    /// Make a downloaded model the one that transcribes.
    ///
    /// Only the setting changes here. `AppDelegate` observes it and reloads the
    /// engine, which is what makes the change take effect — and what discards
    /// whatever was being dictated at the time.
    @discardableResult
    func activate(_ model: TranscriptionModel) -> Bool {
        guard isDownloaded(model) else { return false }
        settings.activeModelID = model.id
        return true
    }

    /// Delete a model's weights.
    ///
    /// The active model is refused rather than hidden behind a disabled button
    /// alone: something has to transcribe, and there is no sensible state where
    /// nothing does.
    @discardableResult
    func remove(_ model: TranscriptionModel) -> Bool {
        guard !isActive(model) else { return false }

        try? FileManager.default.removeItem(at: folder(for: model))
        // The tokenizer WhisperKit fetched alongside the weights, where its
        // folder is named after the variant. Left alone when it is not — a few
        // JSON files are not worth guessing at a path and deleting the wrong
        // thing.
        let tokenizer = baseDirectory.appendingPathComponent("models/openai/whisper-\(model.variant)")
        try? FileManager.default.removeItem(at: tokenizer)

        refresh()
        return true
    }

    /// Fetch the active model if its files have gone — deleted by hand, or
    /// never downloaded because this is a fresh install.
    ///
    /// Awaited before the engine starts, so the first thing that loads the model
    /// finds it there. The alternative is letting WhisperKit download it inside
    /// `load()`, which works but reports nothing to the user for however many
    /// minutes it takes.
    func ensureActiveModelAvailable() async {
        let model = activeModel
        guard !isDownloaded(model) else { return }

        startDownload(model)
        while let task = tasks[model.id] {
            await task.value
        }
    }

    /// The real downloader.
    nonisolated static var whisperKitDownload: Downloader {
        { model, destination, report in
            _ = try await WhisperKit.download(
                variant: model.variant,
                downloadBase: destination,
                progressCallback: { progress in
                    report(progress.fractionCompleted)
                }
            )
        }
    }
}
