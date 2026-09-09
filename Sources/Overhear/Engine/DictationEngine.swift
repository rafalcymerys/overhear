import Foundation
import OnnxRuntimeBindings

/// The dictation loop.
///
/// Idle, it captures audio and throws it away. Activated, it records speech in
/// batches — accumulating chunks until a pause, transcribing that batch, then
/// listening again — and watches every chunk for the cancel word.
actor DictationEngine {
    private let capture: any AudioSource
    private let transcriber: any Transcribing
    private let modelsDirectory: URL

    private var cancelWord: CancelWordListener?

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

    private var isDictating = false
    private var hasAudio = false

    /// Set by `finish()`: the batch being recorded should end where it is and
    /// be transcribed, and dictation should stop once it has.
    ///
    /// Not `isDictating = false`, which is what stopping does — that voids the
    /// batch in progress and drops the result of one already running. This is
    /// the other ending: the one hold to talk's release means.
    private var isFinishing = false

    /// Batches that failed since the last one that worked, or since dictation
    /// was last started by hand. Three in a row is the model rather than the
    /// audio; three spread over an afternoon are three bad batches.
    private static let failuresBeforeGivingUp = 3
    private var consecutiveFailures = 0

    private var hasGivenUp: Bool { consecutiveFailures >= Self.failuresBeforeGivingUp }

    /// Bumped whenever the recording in progress becomes void — the device
    /// went away, or the user stopped. A batch carries the value it began
    /// with and abandons itself when that no longer matches.
    ///
    /// `isDictating` alone cannot carry this. The recorder waits for audio in
    /// a loop that tests the flag, so anything switching dictation off and on
    /// again before the recorder next looks — a resumption, or a fast hand on
    /// the menu — is invisible to it, and the batch swallows the gap as though
    /// nothing happened.
    private var recordingGeneration = 0

    private var resume: ResumeIntent

    /// Whether speech in an unselected language should be translated to
    /// English. Held rather than taken at `start(...)` like `languages`: it
    /// only affects a decode flag, and baking it in would mean reloading the
    /// models to toggle it.
    private var translatesUnsupported = false
    private var languages: [String] = ["en"]
    private var cancelWordPath: String = ""

    init(capture: any AudioSource = AudioCapture(),
         transcriber: any Transcribing = WhisperTranscriber(),
         modelsDirectory: URL = HotWord.modelsDirectory,
         resumeWindow: TimeInterval = 30) {
        self.capture = capture
        self.transcriber = transcriber
        self.modelsDirectory = modelsDirectory
        resume = ResumeIntent(window: resumeWindow)
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
            cancelWord = try CancelWordListener(modelPath: cancelWordPath,
                                               modelsDirectory: modelsDirectory,
                                               env: try ORTEnvironment.shared())
            emit(.status("wake_word_ready"))
        } catch {
            emit(.failed("Failed to load the cancel word model: \(error.localizedDescription)"))
            return
        }

        do {
            try await transcriber.load()
            emit(.status("transcriber_ready"))
        } catch {
            emit(.failed("Failed to load the transcription model: \(error.localizedDescription)"))
            return
        }

        pump = Task { await pumpAudio() }
        loop = Task { await run() }
    }

    func activate() {
        resume.cancel()
        isFinishing = false
        isDictating = true
        consecutiveFailures = 0
    }

    /// End the batch being recorded and stop dictating, keeping what was said.
    ///
    /// What a hold-to-talk release means, and the one way out of a session that
    /// is not a discard: the words spoken up to here still reach the document.
    /// Dictation stops once they have.
    func finish() {
        // Dropped before the guard: a release during a device change answers
        // the question the resumption was holding open, so nothing comes back
        // afterwards with nobody holding a key.
        resume.cancel()
        guard isDictating else { return }
        isFinishing = true
    }

    /// Applied to the next batch — no restart, unlike a language change.
    func setTranslatesUnsupported(_ translates: Bool) {
        translatesUnsupported = translates
    }

    func deactivate() {
        resume.cancel()
        isFinishing = false
        recordingGeneration += 1
        isDictating = false
    }

    func stop() {
        isDictating = false
        isFinishing = false
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
                    resumeIfIntended()
                }
                queue.append(chunk)
                if queue.count > BatchRules.maxQueuedChunks {
                    queue.removeFirst(queue.count - BatchRules.maxQueuedChunks)
                }

            case .interrupted(let reason):
                emit(.warning("Audio device changed: \(reason)"))
                // Dictation does not survive a lost device — the user starts
                // again rather than wondering how much of what they said was
                // heard.
                let wasDictating = isDictating
                recordingGeneration += 1
                isDictating = false
                isFinishing = false
                hasAudio = false
                queue.removeAll()
                cancelWord?.reset()
                if wasDictating {
                    // The utterance is gone either way; the intention to be
                    // dictating is not. Whoever was talking into the old device
                    // means to carry on into the new one.
                    resume.expect()
                    emit(.idle)
                }
            }
        }
    }

    /// Start dictating again for someone who never stopped — the device under
    /// them changed and has now started delivering.
    ///
    /// Nothing here reaches back for the audio that was lost. Dictation picks
    /// up from the first chunk of the new device, so a sentence cut in half by
    /// the switch stays unsaid rather than arriving stitched to whatever
    /// followed it.
    private func resumeIfIntended() {
        guard resume.claim() else { return }
        isDictating = true
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

            if hasGivenUp { return }
            if !Task.isCancelled {
                cancelWord?.reset()
                emit(.idle)
            }
        }
    }

    /// Record and transcribe batches until dictation is switched off.
    private func dictate() async {
        while isDictating, !Task.isCancelled {
            await dictateOneBatch()

            // A release ends the session, but only after the batch it ended has
            // been through transcription — which is the whole of what separates
            // it from a stop.
            guard isFinishing else { continue }
            isFinishing = false
            recordingGeneration += 1
            isDictating = false
        }
    }

    /// Record one batch and transcribe it, or return having emitted why not.
    private func dictateOneBatch() async {
        emit(.ready)

        guard let audio = await recordBatch() else { return }

        emit(.transcribing)
        let result: Transcription
        do {
            result = try await transcriber.transcribe(
                audio,
                languages: languages,
                translatesUnsupported: translatesUnsupported
            )
        } catch {
            let message = "Transcription failed: \(error.localizedDescription)"
            consecutiveFailures += 1
            guard !hasGivenUp else {
                // The failure it has become, not a third lost utterance:
                // nothing said after this would transcribe either.
                isDictating = false
                emit(.failed(message))
                return
            }
            emit(.batchFailed(message))
            return
        }

        consecutiveFailures = 0

        // A cancel word spoken while Whisper was running lands in the
        // backlog, not in the batch that was transcribed. Checking it here
        // is what makes cancelling work right up until the paste.
        if cancelWordInBacklog() {
            emit(.wakeWordCancel)
            return
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

    /// Record one batch of speech.
    ///
    /// Returns audio only if the batch actually finished — on trailing silence
    /// or the duration cap. A batch still being recorded when dictation stops
    /// is dropped: the user asked to stop, so nothing more should reach their
    /// document. The cancel word ends the batch by returning nil.
    private func recordBatch() async -> [Float]? {
        let generation = recordingGeneration
        var chunks: [[Float]] = []
        var silenceChunks = 0
        var heardSpeech = false
        var completed = false

        while isDictating, generation == recordingGeneration, !Task.isCancelled {
            // A release ends the batch where the speaker left off, the way the
            // duration cap does — not where a pause would have ended it, since
            // there may never be one.
            if isFinishing || chunks.count >= BatchRules.maxChunks {
                completed = true
                break
            }

            guard let chunk = await nextChunk(generation) else {
                // Nothing more is coming. A release is the batch ending where
                // the speaker left off; anything else voided it.
                completed = isFinishing
                break
            }

            if cancelWord?.hears(chunk) == true {
                cancelWord?.reset()
                emit(.wakeWordCancel)
                queue.removeAll()
                return nil
            }

            chunks.append(chunk)
            let quiet = BatchRules.isSilent(chunk)

            if !quiet, !heardSpeech {
                heardSpeech = true
                emit(.speechStart)
            }

            if heardSpeech, quiet {
                silenceChunks += 1
                if silenceChunks >= BatchRules.silenceChunksNeeded {
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
    /// Returns nil when dictation is switched off while waiting, when the batch
    /// this belongs to has been voided under it, or when a release has ended
    /// the batch — the recorder must not sit here waiting for audio that would
    /// only arrive after the words it was asked to keep.
    private func nextChunk(_ generation: Int) async -> [Float]? {
        while isDictating, !isFinishing, generation == recordingGeneration, !Task.isCancelled {
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

        for chunk in backlog where cancelWord?.hears(chunk) == true {
            cancelWord?.reset()
            return true
        }

        queue = backlog
        return false
    }

    private func emit(_ event: EngineEvent) {
        continuation?.yield(event)
    }
}
