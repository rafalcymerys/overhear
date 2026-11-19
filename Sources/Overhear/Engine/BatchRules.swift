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

    /// The average level a chunk must reach to start a batch's speech.
    static let silenceThreshold: Float = 0.008

    /// The average level below which a chunk counts towards ending a batch
    /// once speech has started. Lower than the threshold that starts one,
    /// because a sentence trails off: its last words are quieter than its
    /// first, and measuring them against the starting level reads them as the
    /// pause, ending the batch mid-sentence. Not far lower — a room whose
    /// background sits above this would hold every batch to the cap.
    static let endOfSpeechThreshold: Float = 0.005

    /// How much audio from before speech starts is kept at the front of the
    /// batch — enough for a soft first syllable that did not reach the level.
    ///
    /// Everything older is let go. Audio below the level, kept indefinitely,
    /// waits in a batch that never starts until the next real utterance
    /// arrives, and is then transcribed with it: the end of one sentence
    /// pasted at the start of another, after a break.
    static let preRollDuration = 0.5

    /// How much trailing silence ends a batch — the pause the speaker takes
    /// between one utterance and the next.
    static let silenceDuration = 1.5

    /// How long a batch may run before it is handed over anyway. Someone
    /// talking without pause should see text arrive before they stop, and a
    /// batch beyond this is longer than the model wants in one go.
    static let maxDuration = 30.0

    static var silenceChunksNeeded: Int { Int(silenceDuration / chunkDuration) }

    static var maxChunks: Int { Int(maxDuration / chunkDuration) }

    static var preRollChunks: Int { Int((preRollDuration / chunkDuration).rounded(.up)) }

    /// Ten seconds' worth. The handover queue between the microphone and the
    /// recorder is a buffer, not a recording — if something downstream stalls
    /// for longer than that, the audio is stale enough that dropping it beats
    /// growing without limit.
    static let maxQueuedChunks = 125

    /// Whether a chunk is silence: measured against the level that starts
    /// speech until speech has been heard, and against the lower one that ends
    /// it after.
    static func isSilent(_ chunk: [Float], afterSpeech: Bool = false) -> Bool {
        level(of: chunk) < (afterSpeech ? endOfSpeechThreshold : silenceThreshold)
    }

    private static func level(of chunk: [Float]) -> Float {
        guard !chunk.isEmpty else { return 0 }
        let sum = chunk.reduce(Float(0)) { $0 + abs($1) }
        return sum / Float(chunk.count)
    }
}
