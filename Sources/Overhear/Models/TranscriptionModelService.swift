import FluidAudio
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
    /// unannounced inside `WhisperTranscriber.load()`.
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

    private let rootDirectory: URL
    private let download: Downloader
    private let settings: AppSettings
    private var tasks: [String: Task<Void, Never>] = [:]

    /// - Parameters:
    ///   - rootDirectory: where the engines' weights are kept, one directory
    ///     each beneath it. Tests pass a temporary directory.
    ///   - settings: where the active model is stored.
    ///   - download: how to fetch a model.
    init(rootDirectory: URL = TranscriptionModelService.defaultRootDirectory,
         settings: AppSettings? = nil,
         download: @escaping Downloader = TranscriptionModelService.defaultDownload) {
        self.rootDirectory = rootDirectory
        self.settings = settings ?? .shared
        self.download = download
        refresh()
    }

    /// Where the weights live, with one directory per engine beneath it.
    ///
    /// Both libraries default to somewhere unsuitable — WhisperKit to
    /// `~/Documents/huggingface`, FluidAudio to `~/.cache/fluidaudio` — and
    /// neither is the right place for hundreds of megabytes a user never chose
    /// to store: Documents is theirs, it is backed up, and on a Mac with iCloud
    /// Drive enabled it is synced. Application Support is where a cache like
    /// this belongs.
    ///
    /// The engines get their own subdirectories rather than sharing the wake
    /// word models one: each lays out a tree of its own beneath what it is
    /// given, and `HotWordService` lists that same directory looking for the
    /// user's `.onnx` files.
    nonisolated static var defaultRootDirectory: URL {
        HotWord.modelsDirectory.deletingLastPathComponent()
    }

    nonisolated static func defaultBaseDirectory(for engine: TranscriptionEngineKind) -> URL {
        defaultRootDirectory.appendingPathComponent(engine.directoryName)
    }

    private func baseDirectory(for engine: TranscriptionEngineKind) -> URL {
        rootDirectory.appendingPathComponent(engine.directoryName)
    }

    // MARK: - What is on disk

    /// The folder a model's weights land in.
    ///
    /// Each library lays its own tree out beneath the engine's directory, so
    /// these are where their downloads end up rather than paths Overhear chose.
    /// Whisper's must stay exactly as it is: changing it orphans every model
    /// already on disk.
    func folder(for model: TranscriptionModel) -> URL {
        let base = baseDirectory(for: model.engine)
        switch model.engine {
        case .whisper:
            return base
                .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
                .appendingPathComponent("openai_whisper-\(model.variant)")
        case .parakeet:
            return base.appendingPathComponent(model.variant)
        }
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

    /// Whether a model is completely downloaded — which is what tells a
    /// finished download from the directory a cancelled one left behind.
    ///
    /// Parakeet is asked rather than guessed at: a model is four compiled
    /// bundles plus a vocabulary fetched separately, so "contains something
    /// compiled" would call it finished as soon as the first bundle landed, and
    /// `discardPartial` would then refuse to clean up a folder that looks like a
    /// model and cannot load.
    private func hasFiles(for model: TranscriptionModel) -> Bool {
        let folder = folder(for: model)
        switch model.engine {
        case .whisper:
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
                return false
            }
            return contents.contains { $0.hasSuffix(".mlmodelc") }
        case .parakeet:
            guard let variant = ParakeetVariant(model: model) else { return false }
            return AsrModels.modelsExist(
                at: folder,
                version: variant.version,
                encoderPrecision: ParakeetVariant.encoderPrecision
            )
        }
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
            let destination = self.baseDirectory(for: model.engine)
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

        // A download can report success and still leave something that cannot
        // load — a file missing from the snapshot. That is a failure with a
        // Try Again, not a row that quietly goes back to offering Download over
        // a folder nobody will ever clean up.
        guard hasFiles(for: model) else {
            failures[model.id] = "The download finished but the model is incomplete."
            discardPartial(model)
            refresh()
            return
        }

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

    /// Forget a failure so the model goes back to offering a download.
    ///
    /// The setup window's **Choose Another Model**, which is a retreat rather
    /// than a retry: the card has to get its picker back before another model
    /// can be chosen.
    func clearFailure(_ model: TranscriptionModel) {
        failures[model.id] = nil
    }

    /// Wait for whatever is being fetched for this model, if anything is.
    ///
    /// Returns at once when nothing is running, so a caller can await a
    /// download it may or may not have started.
    func waitForDownload(of model: TranscriptionModel) async {
        while let task = tasks[model.id] {
            await task.value
        }
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
        // thing — and Parakeet has no such sibling.
        if model.engine == .whisper {
            let tokenizer = baseDirectory(for: .whisper)
                .appendingPathComponent("models/openai/whisper-\(model.variant)")
            try? FileManager.default.removeItem(at: tokenizer)
        }

        refresh()
        return true
    }

    /// The real downloader: whichever library owns the model.
    ///
    /// One closure rather than one per engine, because it is the seam tests
    /// replace — a dictionary of them would double what a test has to stub to
    /// say the same thing.
    nonisolated static var defaultDownload: Downloader {
        { model, destination, report in
            switch model.engine {
            case .whisper:
                _ = try await WhisperKit.download(
                    variant: model.variant,
                    downloadBase: destination,
                    progressCallback: { progress in
                        report(progress.fractionCompleted)
                    }
                )
            case .parakeet:
                guard let variant = ParakeetVariant(model: model) else {
                    throw EngineError.modelInvalid("Unknown Parakeet model \(model.variant)")
                }
                // `AsrModels.download(to:)` writes to the *parent* of what it is
                // given, under the repository's own folder name, so the
                // directory passed has to already end in that name for what was
                // asked for and what arrives to be the same place.
                let target = destination.appendingPathComponent(variant.variant)
                // Four models and a vocabulary are fetched in turn, each
                // sweeping its own 0 to 1, so the raw fractions would drive the
                // row's progress backwards four times. The encoder is the great
                // majority of the download, which makes the highest fraction
                // seen a close enough approximation without a table of weights
                // that would go stale.
                let furthest = HighWaterMark()
                _ = try await AsrModels.download(
                    to: target,
                    version: variant.version,
                    encoderPrecision: ParakeetVariant.encoderPrecision,
                    progressHandler: { progress in
                        report(furthest.advance(to: progress.fractionCompleted))
                    }
                )
            }
        }
    }
}

/// A progress fraction that only ever goes up.
///
/// A download made of several files reports each one's own 0 to 1; a row that
/// followed those literally would run backwards once per file.
private final class HighWaterMark: @unchecked Sendable {
    private let lock = NSLock()
    private var highest: Double = 0

    func advance(to fraction: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        highest = max(highest, fraction)
        return highest
    }
}
