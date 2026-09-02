import XCTest
@testable import Overhear

/// `Specs/TranscriptionModel.md` — the catalogue, what is on disk, and what
/// activating one model does to the rest.
///
/// Nothing here reaches the network: the downloader is injected, and a
/// "downloaded" model is a folder with a compiled model in it, which is what
/// the service looks for.
@MainActor
final class TranscriptionModelTests: OverhearTestCase {

    // MARK: - The catalogue

    func testGroupsModelsByEngineInAFixedOrder() {
        let parakeet = TranscriptionModel(
            id: "parakeet-test", engine: .parakeet, name: "TDT 0.6B v2",
            variant: "tdt-0.6b-v2", downloadSize: 620 * 1_000_000,
            languageCodes: ["en"], note: nil
        )
        let groups = ModelCatalog.grouped(ModelCatalog.all + [parakeet])

        XCTAssertEqual(groups.map(\.engine), [.whisper, .parakeet])
        XCTAssertEqual(groups[0].models.map(\.name),
                       ["Tiny", "Base", "Base English", "Small", "Large v3 Turbo"])
        XCTAssertEqual(groups[1].models.map(\.name), ["TDT 0.6B v2"])
    }

    /// An engine with nothing to offer gets no heading — a "Parakeet" group
    /// with no rows under it reads as a broken pane.
    func testAnEngineWithNoModelsGetsNoGroup() {
        XCTAssertEqual(ModelCatalog.grouped().map(\.engine), [.whisper])
    }

    /// The pane must never put a repository path in front of anyone.
    func testNoModelIsNamedAfterItsVariant() {
        for model in ModelCatalog.all {
            XCTAssertFalse(model.displayName.contains("openai"), "\(model.displayName) leaks the variant")
            XCTAssertFalse(model.displayName.contains("_"), "\(model.displayName) leaks the variant")
            XCTAssertFalse(model.name.isEmpty)
        }
    }

    func testModelIDsAreUnique() {
        XCTAssertEqual(Set(ModelCatalog.all.map(\.id)).count, ModelCatalog.all.count)
    }

    func testLanguageSummaryReadsAsACountOrAsTheOneLanguage() {
        XCTAssertEqual(ModelCatalog.whisperBase.languageSummary,
                       "\(WhisperLanguage.all.count) languages")
        XCTAssertEqual(ModelCatalog.whisperBaseEnglish.languageSummary, "English only")
    }

    // MARK: - A fresh install

    func testFreshInstallHasWhisperBaseActiveAndNothingDownloaded() {
        let service = makeService()

        XCTAssertEqual(service.activeModel, ModelCatalog.whisperBase)
        XCTAssertTrue(service.downloadedIDs.isEmpty)
        XCTAssertEqual(service.diskUsage, 0)
        XCTAssertEqual(ModelCatalog.all.filter { service.isActive($0) }.count, 1,
                       "exactly one model is active")
    }

    // MARK: - Downloading

    func testDownloadingAModelLeavesItDownloadedButNotActive() async {
        let service = makeService()
        let model = ModelCatalog.whisperSmall

        service.startDownload(model)
        await settle(service, model)

        XCTAssertTrue(service.isDownloaded(model))
        XCTAssertFalse(service.isActive(model), "downloading is not activating")
        XCTAssertEqual(service.activeModel, ModelCatalog.whisperBase)
        XCTAssertNil(service.progress[model.id], "the row goes back to a finished state")
        XCTAssertGreaterThan(service.diskUsage, 0)
    }

    func testProgressIsReportedWhileADownloadRuns() async {
        var reported: [Double] = []
        let service = makeService(download: { model, base, report in
            for fraction in [0.25, 0.5, 0.75] {
                report(fraction)
                await Task.yield()
            }
            Self.writeModel(model, into: base)
        })

        let model = ModelCatalog.whisperSmall
        service.startDownload(model)
        while service.isDownloading(model) {
            if let fraction = service.progress[model.id] { reported.append(fraction) }
            await Task.yield()
        }

        XCTAssertFalse(reported.isEmpty, "the row showed no progress at all")
        XCTAssertEqual(reported, reported.sorted(), "progress went backwards")
    }

    /// Two rows, two downloads, neither one touching the other.
    func testTwoDownloadsRunWithoutDisturbingEachOther() async {
        let service = makeService()
        let first = ModelCatalog.whisperSmall
        let second = ModelCatalog.whisperTiny

        service.startDownload(first)
        service.startDownload(second)
        await settle(service, first)
        await settle(service, second)

        XCTAssertTrue(service.isDownloaded(first))
        XCTAssertTrue(service.isDownloaded(second))
    }

    /// The active model keeps working while something else downloads: the
    /// download only writes files, and never touches the setting the engine
    /// reads.
    func testDownloadingDoesNotDisturbTheActiveModel() async {
        let service = makeService()
        service.startDownload(ModelCatalog.whisperBase)
        await settle(service, ModelCatalog.whisperBase)
        service.activate(ModelCatalog.whisperBase)

        service.startDownload(ModelCatalog.whisperSmall)
        await settle(service, ModelCatalog.whisperSmall)

        XCTAssertEqual(service.activeModel, ModelCatalog.whisperBase)
    }

    func testCancellingADownloadLeavesNoPartialFiles() async {
        let started = Expectation()
        let attempts = TestBox(0)
        let service = makeService(download: { model, base, _ in
            let attempt = attempts.mutate { count -> Int in
                count += 1
                return count
            }
            // Write the half-finished snapshot a real cancel would interrupt.
            try? FileManager.default.createDirectory(
                at: base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/openai_whisper-\(model.variant)"),
                withIntermediateDirectories: true
            )
            guard attempt > 1 else {
                await started.fulfil()
                try await Task.sleep(for: .seconds(30))
                return
            }
            Self.writeModel(model, into: base)
        })

        let model = ModelCatalog.whisperSmall
        service.startDownload(model)
        await started.wait()
        service.cancelDownload(model)

        XCTAssertFalse(service.isDownloaded(model))
        XCTAssertFalse(service.isDownloading(model), "the row goes back to offering Download")
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.folder(for: model).path),
                       "a partial download was left on disk")

        // And it can be started again afterwards.
        service.startDownload(model)
        await settle(service, model)
        XCTAssertTrue(service.isDownloaded(model))
    }

    func testAFailedDownloadIsReportedAndRetryable() async {
        let shouldFail = TestBox(true)
        let service = makeService(download: { model, base, _ in
            if shouldFail.value { throw TestError.offline }
            Self.writeModel(model, into: base)
        })

        let model = ModelCatalog.whisperSmall
        service.startDownload(model)
        await settle(service, model)

        XCTAssertNotNil(service.failures[model.id], "the failure has to be visible in the row")
        XCTAssertFalse(service.isDownloaded(model))
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.folder(for: model).path),
                       "a failed download left files behind")
        XCTAssertEqual(service.activeModel, ModelCatalog.whisperBase, "the active model is untouched")

        shouldFail.value = false
        service.startDownload(model)
        await settle(service, model)

        XCTAssertTrue(service.isDownloaded(model))
        XCTAssertNil(service.failures[model.id], "Try Again cleared the failure")
    }

    // MARK: - Activating

    func testOnlyADownloadedModelCanBeActivated() async {
        let service = makeService()
        let model = ModelCatalog.whisperSmall

        XCTAssertFalse(service.activate(model))
        XCTAssertEqual(service.activeModel, ModelCatalog.whisperBase)

        service.startDownload(model)
        await settle(service, model)

        XCTAssertTrue(service.activate(model))
        XCTAssertEqual(service.activeModel, model)
    }

    func testActivatingMovesTheActiveMarkAndLeavesTheOldModelDownloaded() async {
        let service = makeService()
        for model in [ModelCatalog.whisperBase, ModelCatalog.whisperSmall] {
            service.startDownload(model)
            await settle(service, model)
        }

        service.activate(ModelCatalog.whisperSmall)

        XCTAssertTrue(service.isActive(ModelCatalog.whisperSmall))
        XCTAssertFalse(service.isActive(ModelCatalog.whisperBase))
        XCTAssertTrue(service.isDownloaded(ModelCatalog.whisperBase),
                      "the model that was active stays on disk, ready to switch back to")
        XCTAssertEqual(ModelCatalog.all.filter { service.isActive($0) }.count, 1)
    }

    // MARK: - Removing

    func testRemovingAModelDeletesItsFilesAndFreesTheSpace() async {
        let service = makeService()
        let model = ModelCatalog.whisperSmall
        service.startDownload(model)
        await settle(service, model)
        let used = service.diskUsage

        XCTAssertTrue(service.remove(model))

        XCTAssertFalse(service.isDownloaded(model))
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.folder(for: model).path))
        XCTAssertLessThan(service.diskUsage, used)
        XCTAssertEqual(service.activeModel, ModelCatalog.whisperBase, "the active model is untouched")
    }

    func testTheActiveModelCannotBeRemoved() async {
        let service = makeService()
        let model = ModelCatalog.whisperBase
        service.startDownload(model)
        await settle(service, model)
        service.activate(model)

        XCTAssertFalse(service.remove(model))
        XCTAssertTrue(service.isDownloaded(model))
        XCTAssertTrue(FileManager.default.fileExists(atPath: service.folder(for: model).path))
    }

    func testDiskUsageCountsEveryDownloadedModel() async {
        let service = makeService()
        service.startDownload(ModelCatalog.whisperBase)
        await settle(service, ModelCatalog.whisperBase)
        let one = service.diskUsage

        service.startDownload(ModelCatalog.whisperSmall)
        await settle(service, ModelCatalog.whisperSmall)
        let two = service.diskUsage

        XCTAssertGreaterThan(one, 0)
        XCTAssertGreaterThan(two, one, "the total grows as models are downloaded")

        service.remove(ModelCatalog.whisperSmall)
        XCTAssertEqual(service.diskUsage, one, "and shrinks again when one is removed")
    }

    // MARK: - The active model going missing

    func testTheActiveModelIsFetchedWhenItsFilesAreGone() async {
        let fetched = TestBox<[String]>([])
        let service = makeService(download: { model, base, _ in
            fetched.mutate { $0.append(model.id) }
            Self.writeModel(model, into: base)
        })

        await service.ensureActiveModelAvailable()

        XCTAssertEqual(fetched.value, [ModelCatalog.whisperBase.id],
                       "only the active model is re-fetched")
        XCTAssertTrue(service.isDownloaded(ModelCatalog.whisperBase))
        XCTAssertEqual(service.activeModel, ModelCatalog.whisperBase,
                       "it stays active rather than falling back to another model")
    }

    func testAnAvailableActiveModelIsNotFetchedAgain() async {
        let fetched = TestBox(0)
        let service = makeService(download: { model, base, _ in
            fetched.mutate { $0 += 1 }
            Self.writeModel(model, into: base)
        })

        service.startDownload(ModelCatalog.whisperBase)
        await settle(service, ModelCatalog.whisperBase)
        await service.ensureActiveModelAvailable()

        XCTAssertEqual(fetched.value, 1, "nothing was re-downloaded on the second pass")
    }

    // MARK: - Support

    private func makeService(download: TranscriptionModelService.Downloader? = nil,
                             settings: AppSettings? = nil) -> TranscriptionModelService {
        TranscriptionModelService(
            baseDirectory: tempDirectory,
            settings: settings ?? AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn),
            download: download ?? { model, base, report in
                report(1)
                Self.writeModel(model, into: base)
            }
        )
    }

    /// What a finished download leaves behind: the folder WhisperKit's snapshot
    /// lands in, holding the compiled models.
    nonisolated private static func writeModel(_ model: TranscriptionModel, into base: URL) {
        let folder = base
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent("openai_whisper-\(model.variant)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for part in ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"] {
            let file = folder.appendingPathComponent(part)
            try? Data(repeating: 7, count: 4096).write(to: file)
        }
    }

    /// Wait for whatever the service is doing to a model to finish.
    private func settle(_ service: TranscriptionModelService, _ model: TranscriptionModel) async {
        await waitUntil("\(model.displayName) settles") { !service.isDownloading(model) }
    }
}

private enum TestError: Error, LocalizedError {
    case offline
    var errorDescription: String? { "The network connection was lost." }
}

/// A one-shot signal, for a download that has to be caught mid-flight.
private actor Expectation {
    private var fulfilled = false
    func fulfil() { fulfilled = true }
    func wait() async {
        while !fulfilled { await Task.yield() }
    }
}
