import Foundation
import OnnxRuntimeBindings

/// The dictation loop.
///
/// Idle, it captures audio and throws it away. Activated, it records speech in
/// batches — accumulating chunks until a pause, transcribing that batch, then
/// listening again — and watches every chunk for the cancel word.
actor DictationEngine {
    private static let sampleRate = 16000
    private static let chunkDuration = Double(WakeWordDetector.chunkSamples) / Double(sampleRate)
    private static let silenceThreshold: Float = 0.008
    private static let silenceDuration = 1.5
    private static let maxBatchDuration = 30.0

    private var silenceChunksNeeded: Int { Int(Self.silenceDuration / Self.chunkDuration) }
    private var maxChunks: Int { Int(Self.maxBatchDuration / Self.chunkDuration) }

    private let capture: any AudioSource
    private let transcriber: any Transcribing
    private let modelsDirectory: URL

    private var detector: WakeWordDetector?
    private var environment: ORTEnv?

    private var continuation: AsyncStream<EngineEvent>.Continuation?
    private var loop: Task<Void, Never>?
    private var pump: Task<Void, Never>?

    /// Chunks waiting to be consumed by the recorder. Audio keeps arriving
    /// while Whisper runs, and that backlog is not discarded: it is where a
    /// cancel word spoken *during* transcription is found.
    ///
    /// Filled by `pump` and drained by the loop, which is why the two are
    /// separate tasks: the recorder spends most of its life waiting on this
    /// queue, and if it were also the thing feeding it, nothing would ever
    /// arrive.
    private var queue: [[Float]] = []

    /// Ten seconds. The queue is a handover buffer, not a recording — if
    /// something downstream stalls for longer than that, the audio is stale
    /// enough that dropping it beats growing without limit.
    private static let maxQueuedChunks = 125
    private var isDictating = false
    private var hasAudio = false
    private var languages: [String] = ["en"]
    private var cancelWordPath: String = ""

    init(capture: any AudioSource = AudioCapture(),
         transcriber: any Transcribing = Transcriber(),
         modelsDirectory: URL = HotWord.modelsDirectory) {
        self.capture = capture
        self.transcriber = transcriber
        self.modelsDirectory = modelsDirectory
    }

    func events() -> AsyncStream<EngineEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    /// Load models and start listening. `languages` and `cancelWordPath` are
    /// the two settings baked into an engine at construction, so changing either
    /// one means building a new one.
    func start(languages: [String], cancelWordPath: String) async {
        self.languages = languages.isEmpty ? ["en"] : languages
        self.cancelWordPath = cancelWordPath

        emit(.status("loading_models"))

        do {
            let env = try ORTEnv(loggingLevel: .warning)
            environment = env
            detector = try WakeWordDetector(
                wordModelPath: cancelWordPath,
                featureModels: FeatureModelPaths(
                    melspectrogram: modelsDirectory.appendingPathComponent("melspectrogram.onnx").path,
                    embedding: modelsDirectory.appendingPathComponent("embedding_model.onnx").path
                ),
                env: env
            )
            emit(.status("wake_word_ready"))
        } catch {
            emit(.error("Failed to load the cancel word model: \(error.localizedDescription)"))
            return
        }

        do {
            try await transcriber.load()
            emit(.status("whisper_ready"))
        } catch {
            emit(.error("Failed to load Whisper: \(error.localizedDescription)"))
            return
        }

        pump = Task { await pumpAudio() }
        loop = Task { await run() }
    }

    func activate() {
        isDictating = true
    }

    func deactivate() {
        isDictating = false
    }

    func stop() {
        isDictating = false
        loop?.cancel()
        loop = nil
        pump?.cancel()
        pump = nil
        capture.stop()
        continuation?.finish()
        continuation = nil
    }

    /// Feed the queue from the microphone, and handle a device going away.
    private func pumpAudio() async {
        for await event in capture.events() {
            if Task.isCancelled { return }

            switch event {
            case .chunk(let chunk):
                // The first chunk is proof the input stream is actually
                // delivering, which is the honest moment to call the engine
                // ready rather than merely loaded.
                if !hasAudio {
                    hasAudio = true
                    emit(.idle)
                }
                queue.append(chunk)
                if queue.count > Self.maxQueuedChunks {
                    queue.removeFirst(queue.count - Self.maxQueuedChunks)
                }

            case .interrupted(let reason):
                emit(.warning("Audio device changed: \(reason)"))
                // Dictation does not survive a lost device — the user starts
                // again rather than wondering how much of what they said was
                // heard.
                let wasDictating = isDictating
                isDictating = false
                hasAudio = false
                queue.removeAll()
                detector?.reset()
                if wasDictating {
                    emit(.idle)
                }
            }
        }
    }

    /// Drop audio on the floor while idle; hand it to the recorder while
    /// dictating.
    private func run() async {
        while !Task.isCancelled {
            guard isDictating else {
                queue.removeAll()
                try? await Task.sleep(for: .milliseconds(20))
                continue
            }

            await dictate()

            if !Task.isCancelled {
                detector?.reset()
                emit(.idle)
            }
        }
    }

    /// Record and transcribe batches until dictation is switched off.
    private func dictate() async {
        while isDictating, !Task.isCancelled {
            emit(.ready)

            guard let audio = await recordBatch() else { continue }

            emit(.transcribing)
            let result: Transcription
            do {
                result = try await transcriber.transcribe(audio, languages: languages)
            } catch {
                emit(.error("Transcription failed: \(error.localizedDescription)"))
                continue
            }

            // A cancel word spoken while Whisper was running lands in the
            // backlog, not in the batch that was transcribed. Checking it here
            // is what makes cancelling work right up until the paste.
            if cancelWordInBacklog() {
                emit(.wakeWordCancel)
                continue
            }

            if let language = result.language {
                emit(.languageDetected(language))
            }

            // Transcription can outlive a stop request. Dropping the result
            // keeps the promise that nothing reaches the user's document after
            // they press Stop.
            if !result.text.isEmpty, isDictating {
                emit(.transcription(result.text))
            }
        }
    }

    /// Record one batch of speech.
    ///
    /// Returns audio only if the batch actually finished — on trailing silence
    /// or the duration cap. A batch still being recorded when dictation stops
    /// is dropped: the user asked to stop, so nothing more should reach their
    /// document. The cancel word ends the batch by returning nil.
    private func recordBatch() async -> [Float]? {
        var chunks: [[Float]] = []
        var silenceChunks = 0
        var heardSpeech = false
        var completed = false

        while isDictating, !Task.isCancelled {
            if chunks.count >= maxChunks {
                completed = true
                break
            }

            guard let chunk = await nextChunk() else { return nil }

            if detected(in: chunk) {
                detector?.reset()
                emit(.wakeWordCancel)
                queue.removeAll()
                return nil
            }

            chunks.append(chunk)
            let quiet = isSilent(chunk)

            if !quiet, !heardSpeech {
                heardSpeech = true
                emit(.speechStart)
            }

            if heardSpeech, quiet {
                silenceChunks += 1
                if silenceChunks >= silenceChunksNeeded {
                    completed = true
                    break
                }
            } else {
                silenceChunks = 0
            }
        }

        guard completed, heardSpeech, !chunks.isEmpty else { return nil }
        return chunks.flatMap { $0 }
    }

    /// The next chunk of audio, waiting for capture to deliver one.
    ///
    /// Returns nil when dictation is switched off while waiting, which unwinds
    /// the recorder without emitting anything.
    private func nextChunk() async -> [Float]? {
        while isDictating, !Task.isCancelled {
            if !queue.isEmpty {
                return queue.removeFirst()
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    /// Scan the audio that piled up during transcription for the cancel word.
    ///
    /// When none is found the chunks go back on the queue, so the next batch
    /// does not lose the words the user has already started saying.
    private func cancelWordInBacklog() -> Bool {
        let backlog = queue
        queue.removeAll()

        for chunk in backlog where detected(in: chunk) {
            detector?.reset()
            return true
        }

        queue = backlog
        return false
    }

    private func detected(in chunk: [Float]) -> Bool {
        guard let detector else { return false }
        // The feature models were trained on int16 PCM; capture hands out the
        // conventional -1...1 float range.
        let scaled = chunk.map { $0 * 32767 }
        guard let score = try? detector.predict(scaled) else { return false }
        return score > WakeWordDetector.threshold
    }

    private func isSilent(_ chunk: [Float]) -> Bool {
        guard !chunk.isEmpty else { return true }
        let sum = chunk.reduce(Float(0)) { $0 + abs($1) }
        return sum / Float(chunk.count) < Self.silenceThreshold
    }

    private func emit(_ event: EngineEvent) {
        continuation?.yield(event)
    }
}
