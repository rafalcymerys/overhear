import Foundation

/// The numbers the dictation loop runs on: what counts as silence, how much of
/// it ends a batch, how long one may run before it is handed over regardless,
/// and how much audio may wait to be recorded.
///
/// Apart from the loop that applies them because they are what a reader wants
/// first, and because silence here is a level rather than an absence — a
/// microphone in a quiet room is never actually at zero.
enum BatchRules {
    static let sampleRate = 16000

    /// How much audio one chunk covers.
    static let chunkDuration = Double(WakeWordDetector.chunkSamples) / Double(sampleRate)

    /// The average level below which a chunk is silence.
    static let silenceThreshold: Float = 0.008

    /// How much trailing silence ends a batch — the pause the speaker takes
    /// between one utterance and the next.
    static let silenceDuration = 1.5

    /// How long a batch may run before it is handed over anyway. Someone
    /// talking without pause should see text arrive before they stop, and a
    /// batch beyond this is longer than the model wants in one go.
    static let maxDuration = 30.0

    static var silenceChunksNeeded: Int { Int(silenceDuration / chunkDuration) }

    static var maxChunks: Int { Int(maxDuration / chunkDuration) }

    /// Ten seconds' worth. The handover queue between the microphone and the
    /// recorder is a buffer, not a recording — if something downstream stalls
    /// for longer than that, the audio is stale enough that dropping it beats
    /// growing without limit.
    static let maxQueuedChunks = 125

    static func isSilent(_ chunk: [Float]) -> Bool {
        guard !chunk.isEmpty else { return true }
        let sum = chunk.reduce(Float(0)) { $0 + abs($1) }
        return sum / Float(chunk.count) < silenceThreshold
    }
}
