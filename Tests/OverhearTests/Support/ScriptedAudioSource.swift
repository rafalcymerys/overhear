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

    /// Feed `seconds` of silence — how a batch is brought to an end.
    func sendSilence(seconds: Double) {
        let chunks = Int(seconds * Double(AudioCapture.sampleRate) / Double(WakeWordDetector.chunkSamples))
        for _ in 0..<chunks {
            send(.chunk([Float](repeating: 0, count: WakeWordDetector.chunkSamples)))
        }
    }

    /// Feed `seconds` of audio loud enough to read as speech.
    func sendSpeech(seconds: Double) {
        let chunks = Int(seconds * Double(AudioCapture.sampleRate) / Double(WakeWordDetector.chunkSamples))
        for chunk in 0..<chunks {
            let samples = (0..<WakeWordDetector.chunkSamples).map { sample -> Float in
                let phase = Float(chunk * WakeWordDetector.chunkSamples + sample) * 0.05
                return sin(phase) * 0.3
            }
            send(.chunk(samples))
        }
    }
}
