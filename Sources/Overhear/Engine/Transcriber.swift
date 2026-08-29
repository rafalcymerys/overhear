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
    func transcribe(_ audio: [Float], languages: [String]) async throws -> Transcription
}

/// Speech to text, via WhisperKit's CoreML Whisper.
///
/// Replaces faster-whisper's `base` model with the same Whisper weights
/// converted for CoreML, so accuracy is unchanged and inference moves onto the
/// Neural Engine.
actor Transcriber: Transcribing {
    /// Matching what the Python engine loaded. Small, fast, multilingual.
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
    /// is passed to the decode explicitly — the same two-step the Python engine
    /// used. Whisper transcribes better when told the language than when left
    /// to infer it mid-decode.
    func transcribe(_ audio: [Float], languages: [String]) async throws -> Transcription {
        guard let whisper else { return Transcription(text: "", language: nil) }

        let language = try await resolveLanguage(whisper: whisper, audio: audio, languages: languages)
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            chunkingStrategy: .vad
        )

        let results = try await whisper.transcribe(audioArray: audio, decodeOptions: options)
        let text = results
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Transcription(text: text, language: language)
    }

    /// Which language to decode this batch as.
    ///
    /// One language selected means no detection at all — the user already
    /// answered the question.
    ///
    /// With several, Whisper is asked. This is where the port differs from the
    /// Python engine, and not by choice: faster-whisper returned a probability
    /// for every language, so the old code could rank *within* the selected set
    /// and pick the best of those. WhisperKit's `langProbs` carries only the one
    /// language it sampled — the other entries simply aren't there, and the
    /// values it does carry are log probabilities, so a missing entry cannot be
    /// defaulted to zero and compared. So: take Whisper's answer when it is one
    /// of the user's languages, and otherwise fall back rather than decode as a
    /// language they never asked for.
    private func resolveLanguage(whisper: WhisperKit,
                                 audio: [Float],
                                 languages: [String]) async throws -> String? {
        guard languages.count > 1 else { return languages.first }

        let detection = try await whisper.detectLangauge(audioArray: audio)
        if languages.contains(detection.language) {
            return detection.language
        }
        // Heard something outside the selected set — a half-word, background
        // noise. Sorted rather than first-in-set so the fallback is the same
        // every launch.
        return languages.sorted().first
    }
}
