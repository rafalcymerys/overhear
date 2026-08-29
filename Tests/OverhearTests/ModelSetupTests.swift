import XCTest
@testable import Overhear

@MainActor
final class ModelSetupTests: OverhearTestCase {
    /// Writes a stand-in file wherever a download is requested, and records
    /// what was asked for.
    private final class FakeRemote: @unchecked Sendable {
        private(set) var requested: [String] = []
        var failing: Set<String> = []

        func fetch(_ url: URL) async throws -> URL {
            let name = url.lastPathComponent
            requested.append(name)
            if failing.contains(name) {
                throw URLError(.notConnectedToInternet)
            }
            let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("fake-\(UUID().uuidString)")
            try Data("model".utf8).write(to: temporary)
            return temporary
        }
    }

    func testDownloadsEveryRequiredModelOnFirstRun() async throws {
        let remote = FakeRemote()
        let setup = ModelSetup(directory: tempDirectory, fetch: { try await remote.fetch($0) })

        XCTAssertFalse(setup.isComplete)
        try await setup.ensureModels()

        XCTAssertEqual(Set(remote.requested), Set(ModelSetup.requiredFiles))
        XCTAssertTrue(setup.isComplete)
    }

    /// Every launch after the first: nothing missing, so nothing fetched.
    func testDownloadsNothingWhenModelsArePresent() async throws {
        let remote = FakeRemote()
        let setup = ModelSetup(directory: tempDirectory, fetch: { try await remote.fetch($0) })
        try await setup.ensureModels()

        let second = FakeRemote()
        let again = ModelSetup(directory: tempDirectory, fetch: { try await second.fetch($0) })
        try await again.ensureModels()

        XCTAssertTrue(second.requested.isEmpty)
    }

    /// An interrupted setup must leave the app knowing it is incomplete, so the
    /// next launch finishes the job rather than loading a model that isn't there.
    func testAFailedDownloadReportsAndLeavesSetupIncomplete() async throws {
        let remote = FakeRemote()
        remote.failing = ["embedding_model.onnx"]
        let setup = ModelSetup(directory: tempDirectory, fetch: { try await remote.fetch($0) })

        do {
            try await setup.ensureModels()
            XCTFail("expected the download to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("embedding_model.onnx"))
        }

        XCTAssertFalse(setup.isComplete)
        XCTAssertNotNil(setup.failure)
    }

    func testResolvesBuiltInWordsToDownloadedFiles() {
        let alexa = HotWord.defaultWord
        XCTAssertTrue(alexa.modelPath().hasSuffix("alexa_v0.1.onnx"))
        XCTAssertTrue(ModelSetup.requiredFiles.contains("alexa_v0.1.onnx"))

        // Custom words already carry an absolute path and must be left alone.
        let custom = HotWord.custom(path: "/tmp/my_word.onnx", name: "My Word")
        XCTAssertEqual(custom.modelPath(), "/tmp/my_word.onnx")
    }

    /// Every word offered in Settings needs a model that setup actually fetches.
    func testEveryBuiltInWordIsDownloaded() {
        for word in HotWord.builtIn {
            let file = URL(fileURLWithPath: word.modelPath()).lastPathComponent
            XCTAssertTrue(ModelSetup.requiredFiles.contains(file), "\(word.displayName) has no model to load")
        }
    }
}
