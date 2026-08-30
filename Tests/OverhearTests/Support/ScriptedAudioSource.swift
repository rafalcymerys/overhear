import Foundation
@testable import Overhear

/// An audio source the test drives by hand, so the dictation loop can be
/// exercised without a microphone.
final class ScriptedAudioSource: AudioSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<AudioEvent>.Continuation?
    private var pending: [AudioEvent] = []
    private(set) var isStopped = false

    /// Audio sent before anyone is listening is held rather than dropped.
    /// `EngineController.start()` attaches its consumer inside a Task, so a
    /// test that sends audio straight after calling it would otherwise be
    /// racing the engine rather than testing it.
    func events() -> AsyncStream<AudioEvent> {
        AsyncStream { continuation in
            let backlog: [AudioEvent] = lock.withLock {
                self.continuation = continuation
                defer { pending.removeAll() }
                return pending
            }
            for event in backlog {
                continuation.yield(event)
            }
        }
    }

    func stop() {
        lock.withLock {
            isStopped = true
            continuation?.finish()
            continuation = nil
        }
    }

    func send(_ event: AudioEvent) {
        let target: AsyncStream<AudioEvent>.Continuation? = lock.withLock {
            guard let continuation else {
                pending.append(event)
                return nil
            }
            return continuation
        }
        target?.yield(event)
    }

    /// Feed audio as 1280-sample chunks, the size real capture delivers.
    func send(samples: [Float]) {
        var index = 0
        while index + WakeWordDetector.chunkSamples <= samples.count {
            send(.chunk(Array(samples[index..<(index + WakeWordDetector.chunkSamples)])))
            index += WakeWordDetector.chunkSamples
        }
    }

    /// Feed audio a burst at a time, pausing so the engine can keep up.
    ///
    /// The engine's handover queue holds ten seconds and drops whatever
    /// overflows it, so audio handed over faster than the recorder consumes it
    /// is lost before the recorder ever sees it. Real capture delivers a chunk
    /// every 80ms; this is the same shape, only faster, and it is what any test
    /// feeding more than a few seconds at once wants.
    func sendPaced(samples: [Float], inBurstsOf burst: Int = 8, gap: Duration = .milliseconds(10)) async {
        var index = 0
        var sent = 0
        while index + WakeWordDetector.chunkSamples <= samples.count {
            send(.chunk(Array(samples[index..<(index + WakeWordDetector.chunkSamples)])))
            index += WakeWordDetector.chunkSamples
            sent += 1
            if sent % burst == 0 {
                try? await Task.sleep(for: gap)
            }
        }
    }

    /// Feed `seconds` of silence — how a batch is brought to an end.
    func sendSilence(seconds: Double) {
        send(samples: Self.silence(seconds: seconds))
    }

    /// Feed `seconds` of audio loud enough to read as speech.
    func sendSpeech(seconds: Double) {
        send(samples: Self.speech(seconds: seconds))
    }

    /// Feed `seconds` of speech at a rate the engine can drain.
    func sendPacedSpeech(seconds: Double) async {
        await sendPaced(samples: Self.speech(seconds: seconds))
    }

    static func silence(seconds: Double) -> [Float] {
        [Float](repeating: 0, count: sampleCount(for: seconds))
    }

    /// A tone at a level the engine reads as speech, and that the wake word
    /// models score near zero.
    static func speech(seconds: Double) -> [Float] {
        (0..<sampleCount(for: seconds)).map { sin(Float($0) * 0.05) * 0.3 }
    }

    private static func sampleCount(for seconds: Double) -> Int {
        let chunks = Int(seconds * Double(AudioCapture.sampleRate) / Double(WakeWordDetector.chunkSamples))
        return chunks * WakeWordDetector.chunkSamples
    }
}
