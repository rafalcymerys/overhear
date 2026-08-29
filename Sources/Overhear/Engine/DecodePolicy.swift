import Foundation
import WhisperKit

/// Decides what to tell Whisper about a batch: which language it is in, and
/// whether to transcribe or translate it.
///
/// This matters more than it looks. Whisper is not asked to translate — the
/// task has always been `.transcribe` — but the decoder is prefilled with a
/// language token, and telling it the audio is English when it is Polish makes
/// it render the speech as English anyway. Choosing that token badly is
/// indistinguishable, to the user, from the app translating behind their back.
///
/// The languages the user selected are authoritative: output stays inside them
/// unless translation is deliberately turned on. What makes that safe is that
/// the choice among them is the model's, taken from `LanguageScores`, rather
/// than a fixed rule — a fixed rule is what turned Polish into English.
struct DecodePolicy {
    struct Plan: Equatable {
        var language: String?
        var task: DecodingTask
    }

    /// The languages the user chose, in any order.
    var selected: [String]

    /// Whether speech in a language the user did not select should be
    /// translated to English. Whisper only translates *into* English — there is
    /// a single `<|translate|>` token and no target-language token — so English
    /// is the only destination this can have.
    var translatesUnsupported: Bool

    /// What to decode a batch as, given how the detector scored the languages.
    ///
    /// A single selected language is not a special case. Treating it as one —
    /// skipping detection and forcing that language — made German come back as
    /// English for a user who had only English selected.
    func plan(from scores: LanguageScores?) -> Plan {
        guard let scores, let mostLikely = scores.mostLikely else {
            // Detection could not run. Nothing better to go on than the user's
            // own configuration.
            return Plan(language: selected.first, task: .transcribe)
        }

        // A language the user asked for is transcribed as itself, always. No
        // setting changes this — it is the whole point.
        if selected.contains(mostLikely) {
            return Plan(language: mostLikely, task: .transcribe)
        }

        // Something they did not ask for. Translating it is the one case where
        // leaving their languages is deliberate.
        if translatesUnsupported {
            return Plan(language: mostLikely, task: .translate)
        }

        // Otherwise stay inside the languages they chose, and pick the one the
        // model actually thinks is closest rather than a fixed rule. Whisper
        // mistaking Polish for Czech should still produce Polish, not whichever
        // of their languages happens to sort first.
        // `mostLikely` as the last resort rather than nil: a nil language makes
        // WhisperKit prefill `<|en|>`, which is the outcome all of this exists
        // to prevent.
        let closest = scores.mostLikely(among: selected) ?? selected.first ?? mostLikely
        return Plan(language: closest, task: .transcribe)
    }
}
