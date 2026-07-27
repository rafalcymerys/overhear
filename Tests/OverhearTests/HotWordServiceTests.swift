import XCTest
@testable import Overhear

/// B18–B20 — installing, listing and removing custom cancel word models.
@MainActor
final class HotWordServiceTests: OverhearTestCase {
    nonisolated(unsafe) private var modelsDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        modelsDirectory = tempDirectory.appendingPathComponent("models")
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    private func makeService(download: @escaping HotWordService.Downloader = { _, _ in }) -> HotWordService {
        HotWordService(modelsDirectory: modelsDirectory, download: download)
    }

    private func writeModel(named name: String, contents: String = "onnx-bytes") throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // B18 — install from file

    func testBuiltInWordsAreAlwaysAvailable() {
        let service = makeService()

        XCTAssertEqual(service.customHotWords, [])
        XCTAssertEqual(service.allHotWords.map(\.modelValue),
                       ["alexa", "hey_jarvis", "hey_mycroft", "hey_rhasspy"])
    }

    func testInstallingAModelMakesItAvailable() throws {
        let service = makeService()
        let source = try writeModel(named: "my_word.onnx")

        XCTAssertTrue(service.install(from: source))

        XCTAssertEqual(service.customHotWords.count, 1)
        let installed = try XCTUnwrap(service.customHotWords.first)
        XCTAssertEqual(installed.displayName, "My Word")
        XCTAssertTrue(installed.isCustom)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.modelValue))
    }

    func testDisplayNameIsDerivedFromTheFilename() throws {
        let service = makeService()
        _ = service.install(from: try writeModel(named: "hey-computer_v2.onnx"))

        XCTAssertEqual(service.customHotWords.first?.displayName, "Hey Computer V2")
    }

    func testReinstallingOverwritesRatherThanDuplicating() throws {
        let service = makeService()
        _ = service.install(from: try writeModel(named: "dupe.onnx", contents: "first"))
        _ = service.install(from: try writeModel(named: "dupe.onnx", contents: "second"))

        XCTAssertEqual(service.customHotWords.count, 1)
        let path = try XCTUnwrap(service.customHotWords.first?.modelValue)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "second")
    }

    func testNonModelFilesAreIgnored() throws {
        try "not a model".write(to: modelsDirectory.appendingPathComponent("README.txt"),
                                atomically: true, encoding: .utf8)
        let service = makeService()

        XCTAssertEqual(service.customHotWords, [])
    }

    func testInstalledWordsAreSorted() throws {
        let service = makeService()
        _ = service.install(from: try writeModel(named: "zebra.onnx"))
        _ = service.install(from: try writeModel(named: "apple.onnx"))

        XCTAssertEqual(service.customHotWords.map(\.displayName), ["Apple", "Zebra"])
    }

    // B19 — removal

    func testRemovingDeletesTheFile() throws {
        let service = makeService()
        _ = service.install(from: try writeModel(named: "gone.onnx"))
        let word = try XCTUnwrap(service.customHotWords.first)

        service.remove(word, settings: AppSettings(defaults: makeDefaults(),
                                                   availableHotWords: HotWord.builtIn))

        XCTAssertEqual(service.customHotWords, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: word.modelValue))
    }

    func testRemovingTheSelectedWordFallsBackToTheDefault() throws {
        let service = makeService()
        _ = service.install(from: try writeModel(named: "selected.onnx"))
        let word = try XCTUnwrap(service.customHotWords.first)

        let settings = AppSettings(defaults: makeDefaults(),
                                   availableHotWords: HotWord.builtIn + [word])
        settings.cancelWord = word

        service.remove(word, settings: settings)

        XCTAssertEqual(settings.cancelWord, HotWord.defaultWord,
                       "leaving a deleted path selected would make the engine exit 1")
    }

    func testRemovingAnUnselectedWordLeavesTheSelectionAlone() throws {
        let service = makeService()
        _ = service.install(from: try writeModel(named: "other.onnx"))
        let word = try XCTUnwrap(service.customHotWords.first)

        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        settings.cancelWord = HotWord.builtIn[0]

        service.remove(word, settings: settings)

        XCTAssertEqual(settings.cancelWord, HotWord.builtIn[0])
    }

    // B20 — download validation

    func testInvalidURLIsRejectedWithoutDownloading() {
        var attempted = false
        let service = makeService(download: { _, _ in attempted = true })

        var succeeded: Bool?
        service.downloadFromURL("not a url", completion: { succeeded = $0 })

        XCTAssertEqual(succeeded, false)
        XCTAssertEqual(service.downloadError, "Invalid URL")
        XCTAssertFalse(attempted)
        XCTAssertFalse(service.isDownloading)
    }

    func testNonOnnxURLIsRejectedWithoutDownloading() {
        var attempted = false
        let service = makeService(download: { _, _ in attempted = true })

        var succeeded: Bool?
        service.downloadFromURL("https://example.com/model.bin", completion: { succeeded = $0 })

        XCTAssertEqual(succeeded, false)
        XCTAssertEqual(service.downloadError, "URL must point to an .onnx file")
        XCTAssertFalse(attempted)
    }

    func testSuccessfulDownloadInstallsTheModel() async throws {
        let payload = try writeModel(named: "downloaded-source.onnx", contents: "fetched")
        let service = makeService(download: { _, completion in completion(.success(payload)) })

        var succeeded: Bool?
        service.downloadFromURL("https://example.com/remote_word.onnx", completion: { succeeded = $0 })

        await waitUntil("download to complete") { succeeded != nil }
        XCTAssertEqual(succeeded, true)
        XCTAssertEqual(service.customHotWords.first?.displayName, "Remote Word")
        XCTAssertFalse(service.isDownloading)
        XCTAssertNil(service.downloadError)
    }

    func testFailedDownloadSurfacesTheErrorAndClearsTheFlag() async {
        struct Boom: LocalizedError { var errorDescription: String? { "network is down" } }
        let service = makeService(download: { _, completion in completion(.failure(Boom())) })

        var succeeded: Bool?
        service.downloadFromURL("https://example.com/word.onnx", completion: { succeeded = $0 })

        await waitUntil("download to fail") { succeeded != nil }
        XCTAssertEqual(succeeded, false)
        XCTAssertEqual(service.downloadError, "network is down")
        XCTAssertFalse(service.isDownloading, "a stuck spinner would disable the install buttons")
        XCTAssertEqual(service.customHotWords, [])
    }
}
