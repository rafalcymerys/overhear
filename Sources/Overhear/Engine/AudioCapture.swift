import AVFoundation
import Foundation

/// What a microphone reports.
enum AudioEvent {
    case chunk([Float])
    /// The stream was lost or could not be opened. Capture keeps trying;
    /// dictation does not survive it.
    case interrupted(String)
}

/// Where the engine gets its audio. Implemented by `AudioCapture` in the app
/// and by a scripted stand-in in tests, so the dictation loop can be exercised
/// without a microphone.
protocol AudioSource: Sendable {
    func events() -> AsyncStream<AudioEvent>
    func stop()
}

/// Microphone capture, delivering fixed 1280-sample chunks of 16 kHz mono audio.
///
/// 1280 samples is 80ms, the frame size openWakeWord's feature models were
/// trained on. The input device rarely hands us buffers of that size — it picks
/// its own — so audio is converted, accumulated and re-sliced here, and every
/// chunk that leaves is exactly that length.
///
/// Values are in the conventional -1...1 float range. The wake word models want
/// int16 scaling; that conversion happens at the point of use rather than here,
/// so the same chunks can feed both the detector and Whisper.
final class AudioCapture: AudioSource, @unchecked Sendable {
    /// How long an open stream may go without delivering a buffer before we
    /// treat the device as gone.
    ///
    /// A healthy stream delivers every few tens of milliseconds even in
    /// silence, so this is a wide margin that still notices within seconds.
    /// The watchdog is not redundant with the configuration-change
    /// notification: a device that simply stops producing — asleep USB
    /// interface, a virtual device whose host quit — never posts one.
    static let timeout: TimeInterval = 3.0
    private static let retryInterval: TimeInterval = 1.0

    static let sampleRate: Double = 16000
    static let chunkSamples = WakeWordDetector.chunkSamples

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var accumulator = ChunkAccumulator(chunkSize: AudioCapture.chunkSamples)
    private var lastBuffer = Date.distantPast
    private var continuation: AsyncStream<AudioEvent>.Continuation?
    private var supervisor: Task<Void, Never>?
    private var isTapped = false
    private var configurationObserver: NSObjectProtocol?

    /// Built from the format the buffers actually arrive in, and kept until
    /// that format changes.
    private var converter: AVAudioConverter?

    private lazy var outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Self.sampleRate,
        channels: 1,
        interleaved: false
    )

    /// Start capturing. The stream stays open across device changes: a lost
    /// device produces `.interrupted` and then, once it comes back or another
    /// one takes over, `.chunk` values resume.
    func events() -> AsyncStream<AudioEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
            observeConfigurationChanges()
            supervisor = Task.detached { [weak self] in
                await self?.supervise()
            }
        }
    }

    func stop() {
        supervisor?.cancel()
        supervisor = nil
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        teardown()
        continuation?.finish()
        continuation = nil
    }

    /// Keeps a stream running: opens one, watches that it keeps delivering, and
    /// reopens after any failure.
    private func supervise() async {
        while !Task.isCancelled {
            do {
                try openStream()
            } catch {
                emit(.interrupted(error.localizedDescription))
                try? await Task.sleep(for: .seconds(Self.retryInterval))
                continue
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if silentFor() > Self.timeout {
                    teardown()
                    emit(.interrupted("no audio for \(String(format: "%.1f", silentFor()))s"))
                    break
                }
            }
        }
        teardown()
    }

    private func openStream() throws {
        teardown()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, let outputFormat else {
            throw EngineError.audioUnavailable("no input device")
        }
        guard AVAudioConverter(from: inputFormat, to: outputFormat) != nil else {
            throw EngineError.audioUnavailable("cannot convert \(Int(inputFormat.sampleRate))Hz input")
        }

        // Start the clock before opening, so a stream that never delivers a
        // single buffer is caught by the same watchdog as one that dies later.
        touch()

        // The tap is installed with no format of its own. Handing it the format
        // read a moment ago aborts the process inside AVFAudio — "Input HW
        // format and tap format not matching" — when the device reconfigures
        // between the read and the install, which reopening after a restart
        // makes likely. `nil` means whatever the node is actually producing,
        // and the converter is built from the buffers themselves to match.
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.receive(buffer, to: outputFormat)
        }
        isTapped = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            teardown()
            throw EngineError.audioUnavailable(error.localizedDescription)
        }
    }

    private func teardown() {
        if isTapped {
            engine.inputNode.removeTap(onBus: 0)
            isTapped = false
        }
        if engine.isRunning {
            engine.stop()
        }
        lock.withLock {
            accumulator.reset()
            converter = nil
        }
    }

    /// A device change replaces the engine's input node, which silently
    /// invalidates the tap. Dropping `lastBuffer` makes the watchdog reopen on
    /// its next pass rather than wait out the full timeout.
    private func observeConfigurationChanges() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.lock.withLock { self?.lastBuffer = .distantPast }
        }
    }

    private func receive(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) {
        touch()

        guard let converter = converter(from: buffer.format, to: format) else { return }

        let ratio = format.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = converted.floatChannelData?[0] else { return }

        let samples = UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))
        emitChunks(from: samples)
    }

    /// The converter for the format the buffers are arriving in, rebuilt when
    /// that changes under us — a device swap can hand the same tap a different
    /// sample rate.
    private func converter(from input: AVAudioFormat, to output: AVAudioFormat) -> AVAudioConverter? {
        lock.withLock {
            if let converter, converter.inputFormat == input { return converter }
            converter = AVAudioConverter(from: input, to: output)
            return converter
        }
    }

    private func emitChunks(from samples: UnsafeBufferPointer<Float>) {
        let ready = lock.withLock { accumulator.append(samples) }
        for chunk in ready {
            emit(.chunk(chunk))
        }
    }

    private func emit(_ event: AudioEvent) {
        continuation?.yield(event)
    }

    private func touch() {
        lock.withLock { lastBuffer = Date() }
    }

    private func silentFor() -> TimeInterval {
        lock.withLock { Date().timeIntervalSince(lastBuffer) }
    }
}
