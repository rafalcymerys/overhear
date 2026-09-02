import XCTest
@testable import Overhear

@MainActor
final class WakeWordSetupTests: OverhearTestCase {
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
        let setup = WakeWordSetup(directory: tempDirectory, fetch: { try await remote.fetch($0) })

        XCTAssertFalse(setup.isComplete)
        try await setup.ensureModels()

        // Fetched under the release's versioned asset names...
        XCTAssertEqual(Set(remote.requested), Set(WakeWordSetup.modelAssets.values))
        // ...and stored under the unversioned ones.
        let onDisk = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        XCTAssertEqual(Set(onDisk), Set(WakeWordSetup.requiredFiles))
        XCTAssertTrue(setup.isComplete)
    }

    /// Every launch after the first: nothing missing, so nothing fetched.
    func testDownloadsNothingWhenModelsArePresent() async throws {
        let remote = FakeRemote()
        let setup = WakeWordSetup(directory: tempDirectory, fetch: { try await remote.fetch($0) })
        try await setup.ensureModels()

        let second = FakeRemote()
        let again = WakeWordSetup(directory: tempDirectory, fetch: { try await second.fetch($0) })
        try await again.ensureModels()

        XCTAssertTrue(second.requested.isEmpty)
    }

    /// An interrupted setup must leave the app knowing it is incomplete, so the
    /// next launch finishes the job rather than loading a model that isn't there.
    func testAFailedDownloadReportsAndLeavesSetupIncomplete() async throws {
        let remote = FakeRemote()
        remote.failing = ["embedding_model.onnx"]
        let setup = WakeWordSetup(directory: tempDirectory, fetch: { try await remote.fetch($0) })

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
        XCTAssertTrue(alexa.modelPath().hasSuffix("alexa.onnx"))
        XCTAssertTrue(WakeWordSetup.requiredFiles.contains("alexa.onnx"))

        // Custom words already carry an absolute path and must be left alone.
        let custom = HotWord.custom(path: "/tmp/my_word.onnx", name: "My Word")
        XCTAssertEqual(custom.modelPath(), "/tmp/my_word.onnx")
    }

    /// Setup stores the word models under their own names, not the versioned
    /// ones the release publishes. `HotWordService` turns a filename into a
    /// display name, so a suffix here would reach Settings as "Alexa V0.1".
    func testStoresModelsWithoutTheReleaseVersionSuffix() {
        for file in WakeWordSetup.requiredFiles {
            XCTAssertFalse(file.contains("_v0."), "\(file) would be displayed with its version")
        }
        XCTAssertEqual(WakeWordSetup.modelAssets["alexa.onnx"], "alexa_v0.1.onnx", "but it is fetched from the versioned asset")
    }

    /// Every word offered in Settings needs a model that setup actually fetches.
    func testEveryBuiltInWordIsDownloaded() {
        for word in HotWord.builtIn {
            let file = URL(fileURLWithPath: word.modelPath()).lastPathComponent
            XCTAssertTrue(WakeWordSetup.requiredFiles.contains(file), "\(word.displayName) has no model to load")
        }
    }
}
