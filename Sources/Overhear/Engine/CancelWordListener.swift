import Foundation
import OnnxRuntimeBindings

/// Listens for the cancel word in the audio the engine is recording.
///
/// Over the detector rather than beside it: it knows where the feature models
/// live and what scale they were trained at, and the dictation loop is better
/// off asking whether a chunk had the word in it than knowing either.
struct CancelWordListener {
    private let detector: WakeWordDetector

    /// - Parameters:
    ///   - modelPath: the word model, which is whichever cancel word is chosen.
    ///   - modelsDirectory: where the two feature models the word model is
    ///     stacked on sit.
    init(modelPath: String, modelsDirectory: URL, env: ORTEnv) throws {
        detector = try WakeWordDetector(
            wordModelPath: modelPath,
            featureModels: FeatureModelPaths(
                melspectrogram: modelsDirectory.appendingPathComponent("melspectrogram.onnx").path,
                embedding: modelsDirectory.appendingPathComponent("embedding_model.onnx").path
            ),
            env: env
        )
    }

    /// Whether the cancel word is in this chunk.
    func hears(_ chunk: [Float]) -> Bool {
        // The feature models were trained on int16 PCM; capture hands out the
        // conventional -1...1 float range.
        let scaled = chunk.map { $0 * 32767 }
        guard let score = try? detector.predict(scaled) else { return false }
        return score > WakeWordDetector.threshold
    }

    /// Forget what has been heard so far — between batches, and after the word
    /// has been acted on, so one utterance of it is not found twice.
    func reset() {
        detector.reset()
    }
}
