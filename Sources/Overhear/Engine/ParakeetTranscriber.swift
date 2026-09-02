import FluidAudio
import Foundation
import NaturalLanguage

/// Speech to text, via FluidAudio's CoreML Parakeet.
///
/// NVIDIA's transducer models, converted for CoreML, running on the Neural
/// Engine. Faster than Whisper and, in the v3 build, multilingual across
/// twenty-five European languages.
///
/// The difference that matters is what it will not do. Whisper is *told* which
/// language to decode; Parakeet decides for itself and takes at most a hint,
/// which filters candidate tokens by script rather than fixing the output
/// language. So the selected languages cannot constrain it, and what keeps a
/// transcription inside them is a check after the fact — see `transcribe`.
actor ParakeetTranscriber: Transcribing {
    /// Which model to load. Fixed for the life of the transcriber — activating
    /// another one builds a new transcriber rather than swapping the weights
    /// under this one.
    private let model: TranscriptionModel
    private let variant: ParakeetVariant

    /// Where the Parakeet weights are kept — beside Whisper's rather than in
    /// FluidAudio's own `~/.cache/fluidaudio`, for the same reason Whisper's are
    /// not left in `~/Documents`: it is a cache the user never chose to store.
    static var downloadBase: URL {
        TranscriptionModelService.defaultBaseDirectory(for: .parakeet)
    }

    private var manager: AsrManager?

    init(model: TranscriptionModel = ModelCatalog.defaultModel) {
        self.model = model
        // A Whisper model here would be a programmer error at the factory, not
        // something to fail a dictation over; v3 is the sane fallback.
        variant = ParakeetVariant(model: model) ?? .v3
    }

    /// Load the weights the service has already fetched.
    ///
    /// `load` rather than FluidAudio's `downloadAndLoad`: downloading belongs to
    /// `TranscriptionModelService`, which shows progress and can be cancelled,
    /// and `AppDelegate` waits for it before the engine starts. FluidAudio will
    /// still fetch a missing file from here — which is why the service checks
    /// for a *complete* model rather than for any file at all.
    func load() async throws {
        guard manager == nil else { return }

        let models = try await AsrModels.load(
            from: Self.downloadBase.appendingPathComponent(variant.variant),
            version: variant.version,
            encoderPrecision: ParakeetVariant.encoderPrecision
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
    }

    /// Transcribe one batch of speech.
    ///
    /// `translatesUnsupported` is ignored: Parakeet has no translate task. The
    /// setting is hidden from the General pane while one of these models is
    /// active, rather than left on screen doing nothing.
    func transcribe(_ audio: [Float],
                    languages: [String],
                    translatesUnsupported: Bool) async throws -> Transcription {
        guard let manager else { return Transcription(text: "", language: nil) }

        // Shorter than this and FluidAudio throws. The engine's own batching
        // makes it nearly impossible — speech plus a second and a half of
        // silence — but a throw here would put "Transcription failed" in the
        // menu bar for what was a cough, where the engine already treats empty
        // text as nothing having been said.
        guard audio.count >= ASRConstants.minimumRequiredSamples(forSampleRate: Self.sampleRate) else {
            return Transcription(text: "", language: nil)
        }

        let hint = languages.first.flatMap(Language.init(rawValue:))

        // Fresh per batch. Batches are separated by a pause and can be thrown
        // away whole — a cancel word found in the backlog, or a stop while this
        // is running — so carrying decoder state forward would let speech the
        // user cancelled condition the next utterance.
        var state = try TdtDecoderState(decoderLayers: variant.version.decoderLayers)
        let result = try await manager.transcribe(audio, decoderState: &state, language: hint)

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let spoken = Self.language(of: text)

        // The hint could not stop the model leaving the selected languages, so
        // a transcription that did is dropped rather than pasted. Dropping is
        // what the user asked for by selecting languages at all; pasting Russian
        // into a document from someone who selected English and Polish is the
        // failure this exists to prevent.
        if let spoken, !languages.isEmpty, !languages.contains(spoken) {
            return Transcription(text: "", language: spoken)
        }

        return Transcription(text: text, language: spoken ?? hint?.rawValue)
    }

    /// What language a transcription reads as, or nil when the text is too
    /// short to tell.
    ///
    /// Parakeet reports no language of its own — `ASRResult` carries text,
    /// confidence and timings — so this reads the text rather than the model.
    /// That is weaker than Whisper's detection, which sees the audio, and it is
    /// unreliable on a couple of words, so a short or uncertain answer is no
    /// answer: the transcription is kept rather than dropped on a guess.
    private static func language(of text: String) -> String? {
        guard text.count >= minimumCharactersToJudge else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= minimumConfidence else {
            return nil
        }
        // Regional and script variants come back as "zh-Hans" or "pt-BR"; the
        // selection is in plain codes.
        return language.rawValue.split(separator: "-").first.map(String.init)
    }

    /// What the engine hands over, and what FluidAudio's minimum is measured
    /// against.
    private static let sampleRate = 16000

    /// Below this, language detection is a coin toss — "thanks" and "okay" are
    /// several languages at once.
    private static let minimumCharactersToJudge = 25
    private static let minimumConfidence = 0.65
}
