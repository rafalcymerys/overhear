import Foundation

/// Removes a model's descriptions of non-speech from a transcription.
///
/// Asked to transcribe a cough or a pause, a model often describes the sound
/// instead of transcribing speech — `[ Pause ]`, `[BLANK_AUDIO]`, `(coughing)`,
/// `♪ music ♪`. In a dictation app that text is pasted straight into whatever
/// the user is typing in, so it has to be caught somewhere.
///
/// It runs for every engine. Nothing it strips is text a dictating user wants
/// literally, whichever model produced it, and making it Whisper-only would
/// leave the user's "strip annotations" setting silently doing nothing under
/// another engine.
///
/// For Whisper it has to be caught *here*, rather than by asking the model not
/// to produce it, because both of its own defences are inert in WhisperKit:
/// `DecodingOptions.supressTokens` defaults to empty, with the call that would
/// fill it left commented out and never written, and every segment's
/// `noSpeechProb` is hardcoded to zero, so `noSpeechThreshold` never fires.
///
/// Square brackets and musical notes are removed unconditionally — no one
/// dictates them. Parentheses are a judgement call, since a speaker could
/// plausibly produce one, so they are governed by a setting.
struct AnnotationFilter {
    /// Whether `(...)` counts as an annotation. Off leaves parenthesised text
    /// alone; brackets and notes are stripped either way.
    var stripsParentheses: Bool

    private static let bracketed = "\\[[^\\]]*\\]"
    private static let noted = "♪[^♪]*♪"
    private static let parenthesised = "\\([^)]*\\)"
    /// A note that never got closed, left behind by a truncated batch.
    private static let strayNote = "♪"
    private static let whitespaceRun = "\\s+"

    /// The text with its annotations removed, or an empty string if that is all
    /// it was — which the caller reads as "nothing was said".
    func filter(_ text: String) -> String {
        var patterns = [Self.bracketed, Self.noted, Self.strayNote]
        if stripsParentheses {
            patterns.append(Self.parenthesised)
        }

        var result = text
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        // Removing a span from the middle of a sentence leaves the spaces that
        // sat on either side of it.
        return result
            .replacingOccurrences(of: Self.whitespaceRun, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
