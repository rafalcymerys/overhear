import Foundation
import WhisperKit

/// One batch of speech, turned into text.
struct Transcription: Equatable {
    var text: String
    var language: String?
}

/// How the engine turns audio into text. A protocol so the dictation loop can
/// be tested without loading a multi-hundred-megabyte model.
protocol Transcribing: Sendable {
    func load() async throws
    func transcribe(_ audio: [Float],
                    languages: [String],
                    translatesUnsupported: Bool) async throws -> Transcription
}

/// Speech to text, via WhisperKit's CoreML Whisper.
///
/// The weights are Whisper's own, converted for CoreML, so inference runs on the
/// Neural Engine rather than the CPU.
actor Transcriber: Transcribing {
    /// Small, fast and multilingual — the balance dictation wants, where a
    /// batch has to come back before the user has finished their next sentence.
    static let modelVariant = "base"

    /// Where the Whisper weights are kept.
    ///
    /// WhisperKit defaults to `~/Documents/huggingface`, which is the wrong
    /// place for 150MB of model weights a user never chose to store: Documents
    /// is theirs, it is backed up, and on a Mac with iCloud Drive enabled it is
    /// synced. Application Support is where a cache like this belongs.
    ///
    /// It gets its own subdirectory rather than sharing the wake word models
    /// one: WhisperKit creates a `models/<org>/<repo>` tree beneath whatever it
    /// is given, and `HotWordService` lists that same directory looking for the
    /// user's `.onnx` files.
    static var downloadBase: URL {
        HotWord.modelsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("whisper")
    }

    private var whisper: WhisperKit?

    /// Load the model, downloading and compiling it if this is the first run —
    /// slow enough on that first run to be worth a status event.
    func load() async throws {
        guard whisper == nil else { return }
        whisper = try await WhisperKit(WhisperKitConfig(
            model: Self.modelVariant,
            downloadBase: Self.downloadBase,
            verbose: false,
            logLevel: .error
        ))
    }

    /// Transcribe one batch of speech.
    ///
    /// With several languages configured, detection runs first and its result
    /// is passed to the decode explicitly: Whisper transcribes better when told
    /// the language than when left to infer it mid-decode. What to do with that
    /// answer is `DecodePolicy`'s decision, not this method's.
    func transcribe(_ audio: [Float],
                    languages: [String],
                    translatesUnsupported: Bool) async throws -> Transcription {
        guard let whisper else { return Transcription(text: "", language: nil) }

        let scores = try await LanguageDetector.scores(for: audio, using: whisper)
        let policy = DecodePolicy(selected: languages, translatesUnsupported: translatesUnsupported)
        let plan = policy.plan(from: scores)

        let options = DecodingOptions(
            verbose: false,
            task: plan.task,
            language: plan.language,
            chunkingStrategy: .vad
        )

        let results = try await whisper.transcribe(audioArray: audio, decodeOptions: options)
        let text = results
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Transcription(text: text, language: plan.language)
    }

}
