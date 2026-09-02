import Foundation

/// One batch of speech, turned into text.
struct Transcription: Equatable {
    var text: String
    var language: String?
}

/// How the engine turns audio into text. A protocol so the dictation loop can
/// be tested without loading a multi-hundred-megabyte model — and so a second
/// engine can be dropped in beside Whisper without the loop noticing.
///
/// `languages` is the user's selection, not a Whisper concept: what an engine
/// does with it is its own business. `translatesUnsupported` is Whisper's alone
/// — Parakeet has no translate task, and the setting is hidden while one of its
/// models is active rather than left to do nothing.
protocol Transcribing: Sendable {
    func load() async throws
    func transcribe(_ audio: [Float],
                    languages: [String],
                    translatesUnsupported: Bool) async throws -> Transcription
}

/// Which transcriber runs a given model.
///
/// A named type rather than a closure inside `EngineController`'s default
/// argument, because a default argument cannot be tested — and "activating the
/// Parakeet row builds a Parakeet transcriber" is the thing about a second
/// engine that would otherwise fail silently.
enum TranscriberFactory {
    static func make(for model: TranscriptionModel) -> any Transcribing {
        switch model.engine {
        case .whisper: return WhisperTranscriber(model: model)
        case .parakeet: return ParakeetTranscriber(model: model)
        }
    }
}
