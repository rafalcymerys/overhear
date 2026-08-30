import OnnxRuntimeBindings
import XCTest
@testable import Overhear

/// The test that proves the openWakeWord port.
///
/// `WakeWordDetector` reimplements a pipeline whose buffering was fixed by how
/// the classifier heads were trained — a window off by one frame still runs and
/// still returns a number, it just returns a wrong one. So the assertions here
/// are against scores measured by running openWakeWord's own reference
/// implementation over these exact clips: 0.999999 for "alexa", 0.000328 for
/// unrelated speech.
final class WakeWordDetectorTests: XCTestCase {
    /// Models are shared across tests and across runs — six files, ~6MB, and
    /// re-downloading them per test would dominate the suite.
    private static var modelsDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("overhear-test-models")
    }

    override func setUp() async throws {
        try await super.setUp()
        let setup = await ModelSetup(directory: Self.modelsDirectory)
        try await setup.ensureModels()
    }

    func testScoresWakeWordNearCertainty() throws {
        let detector = try makeDetector()
        let score = try highestScore(detector: detector, sample: .alexa)
        XCTAssertEqual(score, 0.999999, accuracy: 0.0001, "matches openWakeWord's reference score for this clip")
    }

    func testIgnoresUnrelatedSpeech() throws {
        let detector = try makeDetector()
        let score = try highestScore(detector: detector, sample: .sentenceEn)
        XCTAssertEqual(score, 0.000328, accuracy: 0.0001, "matches openWakeWord's reference score for this clip")
    }

    /// A reset has to leave the detector able to hear the word again — that is
    /// what happens after every cancel.
    func testDetectsAgainAfterReset() throws {
        let detector = try makeDetector()
        let first = try highestScore(detector: detector, sample: .alexa)
        detector.reset()
        let second = try highestScore(detector: detector, sample: .alexa)
        XCTAssertGreaterThan(first, 0.9)
        XCTAssertGreaterThan(second, 0.9)
    }

    private func makeDetector() throws -> WakeWordDetector {
        let env = try ORTEnv(loggingLevel: .warning)
        let directory = Self.modelsDirectory
        return try WakeWordDetector(
            // Resolved the way the app resolves it, so a change to how models
            // are named on disk fails the assertion rather than the file lookup.
            wordModelPath: HotWord.defaultWord.modelPath(in: directory),
            featureModels: FeatureModelPaths(
                melspectrogram: directory.appendingPathComponent("melspectrogram.onnx").path,
                embedding: directory.appendingPathComponent("embedding_model.onnx").path
            ),
            env: env
        )
    }

    private func highestScore(detector: WakeWordDetector, sample: SyntheticSample) throws -> Float {
        let samples = try padded(sample)
        var best: Float = 0
        var index = 0
        while index + WakeWordDetector.chunkSamples <= samples.count {
            let chunk = Array(samples[index..<(index + WakeWordDetector.chunkSamples)])
            best = max(best, try detector.predict(chunk))
            index += WakeWordDetector.chunkSamples
        }
        return best
    }

    /// A sample as int16-scaled floats, padded with a second of silence at each
    /// end. The padding matches how openWakeWord evaluates clips: a short
    /// utterance with no lead-in never fills the 16-frame window.
    private func padded(_ sample: SyntheticSample) throws -> [Float] {
        let padding = [Float](repeating: 0, count: 16000)
        return padding + (try sample.loadForDetector()) + padding
    }
}
