import CoreML
import Foundation
import WhisperKit

/// What Whisper thinks a batch could be, scored language by language.
struct LanguageScores: Equatable {
    /// Language code to the score Whisper gave it. Higher is more likely.
    var scores: [String: Float]

    /// The language Whisper would pick left to itself.
    var mostLikely: String? {
        scores.max { $0.value < $1.value }?.key
    }

    /// The likeliest of a given set — how the user's chosen languages get
    /// ranked against each other rather than against all hundred.
    func mostLikely(among codes: [String]) -> String? {
        codes
            .compactMap { code in scores[code].map { (code, $0) } }
            .max { $0.1 < $1.1 }?
            .0
    }
}

/// Runs Whisper's language detection and keeps every language's score, not just
/// the winner.
///
/// `WhisperKit.detectLangauge` reports only the one language it sampled, which
/// is not enough: when it picks something the user did not select, we need to
/// know which of *their* languages came closest. Answering that with a fixed
/// rule instead — the alphabetically first, or a configured default — is what
/// turned Polish into English (R-98).
///
/// So this repeats what `detectLangauge` does, using WhisperKit's public
/// pipeline, and substitutes a sampler that reads the whole language row of the
/// logits on the way past. It costs one detection pass, the same as before.
enum LanguageDetector {
    static func scores(for audio: [Float], using whisper: WhisperKit) async throws -> LanguageScores {
        // The tokenizer only exists once the models are in memory, and
        // `detectLangauge` does this for itself — this path has to as well.
        if whisper.modelState != .loaded {
            try await whisper.loadModels()
        }
        guard let tokenizer = whisper.tokenizer else {
            throw EngineError.modelInvalid("Whisper tokenizer unavailable")
        }

        let options = DecodingOptions(verbose: false)
        let decoderInputs = try whisper.textDecoder.prepareDecoderInputs(
            withPrompt: [tokenizer.specialTokens.startOfTranscriptToken]
        )

        // Language detection only ever looks at the first window.
        guard let samples = whisper.audioProcessor.padOrTrim(
            fromArray: audio,
            startAt: 0,
            toLength: whisper.featureExtractor.windowSamples ?? Constants.defaultWindowSamples
        ) else {
            throw EngineError.modelInvalid("Could not prepare audio for language detection")
        }
        guard let mel = try await whisper.featureExtractor.logMelSpectrogram(fromAudio: samples) else {
            throw EngineError.modelInvalid("Could not compute mel spectrogram")
        }
        guard let encoded = try await whisper.audioEncoder.encodeFeatures(mel) else {
            throw EngineError.modelInvalid("Could not encode audio features")
        }

        let sampler = ScoringSampler(languageTokens: tokenizer.allLanguageTokens)
        _ = try await whisper.textDecoder.detectLanguage(
            from: encoded,
            using: decoderInputs,
            sampler: sampler,
            options: options,
            temperature: 0
        )

        var scores: [String: Float] = [:]
        for (token, score) in sampler.captured {
            let code = tokenizer.decode(tokens: [token])
                .replacingOccurrences(of: "<|", with: "")
                .replacingOccurrences(of: "|>", with: "")
            guard !code.isEmpty else { continue }
            scores[code] = score
        }
        return LanguageScores(scores: scores)
    }
}

/// A sampler that records the logits it was handed before behaving like the
/// greedy one WhisperKit would otherwise have used.
///
/// By the time detection reaches the sampler the logits have already been
/// filtered so only language tokens carry a real value; everything else is
/// negative infinity. Reading them here is the whole trick — no extra
/// inference, just the numbers that were computed anyway.
private final class ScoringSampler: TokenSampling {
    private(set) var captured: [Int: Float] = [:]
    private let languageTokens: Set<Int>

    init(languageTokens: Set<Int>) {
        self.languageTokens = languageTokens
    }

    func update(tokens: [Int], logits: MLMultiArray, logProbs: [Float]) -> SamplingResult {
        var best: (token: Int, score: Float)?

        for token in languageTokens where token < logits.count {
            let score = logits[token].floatValue
            guard score.isFinite else { continue }
            captured[token] = score
            if best == nil || score > best!.score {
                best = (token, score)
            }
        }

        guard let best else {
            return SamplingResult(tokens: tokens, logProbs: logProbs, completed: true)
        }
        return SamplingResult(
            tokens: tokens + [best.token],
            logProbs: logProbs + [best.score],
            completed: true
        )
    }

    func finalize(tokens: [Int], logProbs: [Float]) -> SamplingResult {
        SamplingResult(tokens: tokens, logProbs: logProbs, completed: true)
    }
}
