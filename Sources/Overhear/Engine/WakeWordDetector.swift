import Foundation
import OnnxRuntimeBindings

/// Wake word detection, ported from openWakeWord's streaming inference.
///
/// Three ONNX graphs in sequence, the same files the Python engine used:
///
/// 1. `melspectrogram.onnx` turns raw 16 kHz samples into 32-bin mel frames,
/// 2. Google's `embedding_model.onnx` turns a 76-frame window into a 96-value
///    vector,
/// 3. the wake word head scores the last 16 of those vectors.
///
/// Only step 3 is per-word, which is why a custom `.onnx` a user installs is a
/// few hundred kilobytes rather than a whole model: it rides on the two shared
/// feature models.
///
/// The buffering below mirrors `AudioFeatures._streaming_features` in
/// openwakeword/utils.py frame for frame. It looks arbitrary because it is —
/// the classifier heads were trained against exactly this pipeline, and an
/// off-by-one in the window would score in-distribution audio as noise.
final class WakeWordDetector {
    /// 80ms at 16 kHz. Everything downstream assumes chunks of exactly this size.
    static let chunkSamples = 1280

    /// The mel model sees the new chunk plus three hops of history, so the
    /// frames at the chunk boundary have the context they were trained with.
    private static let melInputSamples = chunkSamples + 160 * 3
    private static let melBins = 32
    private static let embeddingWindow = 76
    private static let embeddingSize = 96
    private static let melBufferMax = 10 * 97
    private static let featureBufferMax = 120
    private static let predictionFrames = 16
    private static let rawBufferMax = 16000 * 10

    /// openWakeWord's default. A cancel word is a deliberate, isolated
    /// utterance, so this sits well clear of conversational speech.
    static let threshold: Float = 0.5

    private let melModel: ONNXModel
    private let embeddingModel: ONNXModel
    private let wordModel: ONNXModel

    private var rawBuffer: [Float] = []
    private var melBuffer: [Float]
    private var featureBuffer: [Float]

    /// Embeddings of four seconds of noise, computed once at load.
    ///
    /// openWakeWord seeds its feature buffer this way on every reset. Without
    /// it the first sixteen frames after a reset would be scored against zeros,
    /// which is nowhere near anything the head saw in training and produces
    /// junk scores for the first ~1.3s. Caching the seed keeps `reset()` free
    /// and makes detection deterministic run to run.
    private let seedFeatures: [Float]

    init(wordModelPath: String, featureModels: FeatureModelPaths, env: ORTEnv) throws {
        melModel = try ONNXModel(path: featureModels.melspectrogram, env: env)
        embeddingModel = try ONNXModel(path: featureModels.embedding, env: env)
        wordModel = try ONNXModel(path: wordModelPath, env: env)

        melBuffer = Self.initialMelBuffer()
        featureBuffer = []
        seedFeatures = try Self.seedFeatures(mel: melModel, embedding: embeddingModel)
        featureBuffer = seedFeatures
    }

    /// Score one 1280-sample chunk. Input is float audio scaled to int16 range,
    /// which is what the mel model expects.
    func predict(_ chunk: [Float]) throws -> Float {
        rawBuffer.append(contentsOf: chunk)
        if rawBuffer.count > Self.rawBufferMax {
            rawBuffer.removeFirst(rawBuffer.count - Self.rawBufferMax)
        }
        // The mel model's first convolution needs a minimum window; below this
        // there is nothing to score yet.
        guard rawBuffer.count >= 400 else { return 0 }

        let melInput = Array(rawBuffer.suffix(Self.melInputSamples))
        let mel = try melModel.run(melInput, shape: [1, melInput.count])
        // Brings the ONNX melspectrogram's range in line with the TensorFlow
        // implementation the embedding model was trained against.
        melBuffer.append(contentsOf: mel.values.map { $0 / 10 + 2 })

        let maxMelValues = Self.melBufferMax * Self.melBins
        if melBuffer.count > maxMelValues {
            melBuffer.removeFirst(melBuffer.count - maxMelValues)
        }

        let windowValues = Self.embeddingWindow * Self.melBins
        guard melBuffer.count >= windowValues else { return 0 }

        let window = Array(melBuffer.suffix(windowValues))
        let embedding = try embeddingModel.run(
            window,
            shape: [1, Self.embeddingWindow, Self.melBins, 1]
        )
        featureBuffer.append(contentsOf: embedding.values)

        let maxFeatureValues = Self.featureBufferMax * Self.embeddingSize
        if featureBuffer.count > maxFeatureValues {
            featureBuffer.removeFirst(featureBuffer.count - maxFeatureValues)
        }

        let predictionValues = Self.predictionFrames * Self.embeddingSize
        guard featureBuffer.count >= predictionValues else { return 0 }

        let features = Array(featureBuffer.suffix(predictionValues))
        let score = try wordModel.run(
            features,
            shape: [1, Self.predictionFrames, Self.embeddingSize]
        )
        return score.values.first ?? 0
    }

    /// Forget everything heard so far.
    ///
    /// Called after a detection so the same utterance cannot fire twice as it
    /// slides out of the 16-frame window.
    func reset() {
        rawBuffer.removeAll(keepingCapacity: true)
        melBuffer = Self.initialMelBuffer()
        featureBuffer = seedFeatures
    }

    private static func initialMelBuffer() -> [Float] {
        Array(repeating: 1, count: embeddingWindow * melBins)
    }

    /// Four seconds of noise pushed through the feature models, windowed the
    /// way openWakeWord windows it. Seeded so two runs produce the same buffer.
    private static func seedFeatures(mel: ONNXModel, embedding: ONNXModel) throws -> [Float] {
        var rng = SeededGenerator(seed: 0x0776_0577)
        let noise = (0..<(16000 * 4)).map { _ in Float(Int.random(in: -1000..<1000, using: &rng)) }

        let spectrogram = try mel.run(noise, shape: [1, noise.count])
        let values = spectrogram.values.map { $0 / 10 + 2 }
        let frames = values.count / melBins

        var features: [Float] = []
        var start = 0
        while start + embeddingWindow <= frames {
            let window = Array(values[(start * melBins)..<((start + embeddingWindow) * melBins)])
            let result = try embedding.run(window, shape: [1, embeddingWindow, melBins, 1])
            features.append(contentsOf: result.values)
            start += 8
        }

        let maxValues = featureBufferMax * embeddingSize
        return features.count > maxValues ? Array(features.suffix(maxValues)) : features
    }
}

/// Where the two shared feature models live on disk.
struct FeatureModelPaths {
    var melspectrogram: String
    var embedding: String
}

/// A small deterministic PRNG, so the seed noise is identical every launch.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
