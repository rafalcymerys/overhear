import FluidAudio
import XCTest
@testable import Overhear

/// `Specs/TranscriptionModel.md` for the second engine: that the catalogue
/// agrees with FluidAudio about names and languages, that the service handles
/// Parakeet's own layout, and that activating one of its models builds a
/// transcriber that can actually run it.
@MainActor
final class ParakeetModelTests: OverhearTestCase {

    /// The catalogue and FluidAudio have to agree on the directory name, or a
    /// download lands somewhere the service never looks.
    func testParakeetVariantsMatchTheLibrarysOwnFolderNames() {
        XCTAssertEqual(ModelCatalog.parakeetV2.variant, Repo.parakeetV2.folderName)
        XCTAssertEqual(ModelCatalog.parakeetV3.variant, Repo.parakeetV3.folderName)
    }

    /// Every language claimed for v3 has to be one the picker can show and the
    /// decode hint can name. A code that fails either is a language offered to
    /// the user that nothing downstream understands.
    func testEveryParakeetLanguageIsOneTheAppAndTheHintKnow() {
        let claimed = ModelCatalog.parakeetV3.languageCodes ?? []
        XCTAssertEqual(claimed.count, 24)

        for code in claimed.sorted() {
            XCTAssertNotNil(Language(rawValue: code), "\(code) is not a language the hint can name")
            XCTAssertTrue(RecognitionLanguage.all.contains { $0.code == code },
                          "\(code) is not in the picker")
        }
    }

    func testAParakeetModelDownloadsActivatesAndIsRemoved() async {
        let service = makeModelService()
        let model = ModelCatalog.parakeetV3

        service.startDownload(model)
        await settle(service, model)
        XCTAssertTrue(service.isDownloaded(model))

        // Base has to be downloaded before anything else can be activated over
        // it, so activate Parakeet and check the mark moved.
        XCTAssertTrue(service.activate(model))
        XCTAssertEqual(service.activeModel, model)
        XCTAssertFalse(service.remove(model), "the active model cannot be removed")

        service.startDownload(ModelCatalog.whisperBase)
        await settle(service, ModelCatalog.whisperBase)
        service.activate(ModelCatalog.whisperBase)

        XCTAssertTrue(service.remove(model))
        XCTAssertFalse(service.isDownloaded(model))
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.folder(for: model).path))
    }

    /// A Parakeet model is four compiled bundles and a vocabulary fetched
    /// separately. Counting it as downloaded before the vocabulary lands leaves
    /// a folder that looks like a model and cannot load.
    func testAParakeetModelWithoutItsVocabularyIsNotDownloaded() async {
        let service = makeModelService(download: { model, base, _ in
            FakeModelDownload.write(model, into: base, includingVocabulary: false)
        })
        let model = ModelCatalog.parakeetV3

        service.startDownload(model)
        await settle(service, model)

        XCTAssertFalse(service.isDownloaded(model), "an incomplete model must not count")
        XCTAssertNotNil(service.failures[model.id], "the user has to be told, and offered a retry")
        XCTAssertFalse(FileManager.default.fileExists(atPath: service.folder(for: model).path),
                       "the partial download should have been discarded")
    }

    /// The one path that must never move: users have hundreds of megabytes
    /// under it, and a model the service cannot find is a model it downloads
    /// again.
    func testWhisperModelsStayWhereTheyHaveAlwaysBeen() {
        let service = makeModelService()
        let folder = service.folder(for: ModelCatalog.whisperBase)

        XCTAssertEqual(
            folder.path,
            tempDirectory
                .appendingPathComponent("whisper/models/argmaxinc/whisperkit-coreml/openai_whisper-base")
                .path
        )
    }

    /// Which transcriber a model gets. The one thing about a second engine that
    /// fails silently: a Parakeet row that builds a Whisper transcriber would
    /// download half a gigabyte and then transcribe with the wrong weights.
    func testTheFactoryBuildsTheEngineTheModelNames() {
        for model in ModelCatalog.all {
            let transcriber = TranscriberFactory.make(for: model)
            switch model.engine {
            case .whisper:
                XCTAssertTrue(transcriber is WhisperTranscriber, "\(model.displayName) got the wrong engine")
            case .parakeet:
                XCTAssertTrue(transcriber is ParakeetTranscriber, "\(model.displayName) got the wrong engine")
            }
        }
    }
    /// Activating a model has to load different weights, which is a new
    /// transcriber. Restarting for anything else — a language, the cancel word
    /// — must not be, or every toggle would cost a model load.
    func testANewTranscriberIsBuiltOnlyWhenTheModelChanges() async throws {
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        let requested = TestBox<[String]>([])
        let audio = ScriptedAudioSource()
        let controller = EngineController(
            appState: AppState(),
            injector: SpyInjector(),
            modelsDirectory: EngineTestModels.directory,
            makeTranscriber: { model in
                requested.mutate { $0.append(model.id) }
                return StubTranscriber()
            },
            makeAudioSource: { audio },
            settings: settings
        )
        defer { controller.stop() }

        controller.start()
        XCTAssertEqual(requested.value, [ModelCatalog.whisperBase.id])

        // A restart with the same model reuses the loaded one.
        controller.stop()
        controller.start()
        XCTAssertEqual(requested.value, [ModelCatalog.whisperBase.id],
                       "restarting must not reload the same weights")

        settings.activeModelID = ModelCatalog.whisperSmall.id
        controller.stop()
        controller.start()
        XCTAssertEqual(requested.value, [ModelCatalog.whisperBase.id, ModelCatalog.whisperSmall.id])

        // And across engines, where the weights have nothing in common.
        settings.activeModelID = ModelCatalog.parakeetV3.id
        controller.stop()
        controller.start()
        XCTAssertEqual(requested.value, [ModelCatalog.whisperBase.id,
                                         ModelCatalog.whisperSmall.id,
                                         ModelCatalog.parakeetV3.id])
    }

}
