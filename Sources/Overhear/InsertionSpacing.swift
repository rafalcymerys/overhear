import Foundation

/// Separates what is being inserted from what is already in the field.
///
/// Dictation rarely lands in an empty document — it arrives after a word
/// someone just typed, or in the middle of a sentence they went back to — and
/// pasting the transcription verbatim welds it to whatever it landed against.
///
/// Both sides run through one rule over the pair of characters meeting at the
/// caret: the existing character and the first of the insertion on the way in,
/// the last of the insertion and the existing character on the way out. Which
/// is why the two sets it consults are not symmetrical. A character that opens
/// something disqualifies the pair from the left, punctuation that attaches to
/// the word in front of it disqualifies the pair from the right, and each is
/// only ever asked about the side it can speak for. `Specs/Spacing.md`.
enum InsertionSpacing {
    static func apply(to text: String, in context: CaretContext) -> String {
        guard let first = text.first, let last = text.last else { return text }

        let leading = wantsSpace(between: context.characterBefore, and: first)
        let trailing = wantsSpace(between: last, and: context.after)

        return (leading ? " " : "") + text + (trailing ? " " : "")
    }

    private static func wantsSpace(between left: Character?, and right: Character?) -> Bool {
        guard let left, let right else { return false }
        // Whichever side brought it, whitespace already there is the separation.
        guard !left.isWhitespace, !right.isWhitespace else { return false }
        guard !opensSomething(left), !attachesToWhatCameBefore(right) else { return false }
        return !(writtenWithoutSpaces(left) && writtenWithoutSpaces(right))
    }

    /// Characters that take what follows them without a gap.
    ///
    /// The straight quotes are in both sets. Nothing in the field says which
    /// end of a pair a `"` is, so it suppresses a space from either side —
    /// wrong only in the case where the user wanted one, and there they can
    /// type it.
    private static let opening: Set<Character> = ["(", "[", "{", "\"", "'", "\u{201C}", "\u{2018}", "¿", "¡"]

    /// Punctuation that belongs to the word in front of it. An insertion before
    /// one of these takes no space, or the mark is pushed off the word it ends.
    private static let attaching: Set<Character> = [
        ".", ",", ";", ":", "!", "?", ")", "]", "}", "\"", "'", "\u{201D}", "\u{2019}"
    ]

    private static func opensSomething(_ character: Character) -> Bool {
        opening.contains(character)
    }

    private static func attachesToWhatCameBefore(_ character: Character) -> Bool {
        attaching.contains(character)
    }

    /// Scripts that separate words without a space, where adding one is an
    /// error rather than a courtesy.
    ///
    /// Asked of both characters, never one: Chinese inserted after English
    /// still takes a space, and so does English inserted after Chinese. It is
    /// the pair meeting at the caret that decides, not the language of the
    /// utterance.
    private static func writtenWithoutSpaces(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return spacelessScripts.contains { $0.contains(scalar.value) }
    }

    private static let spacelessScripts: [ClosedRange<UInt32>] = [
        0x0E00...0x0E7F,      // Thai
        0x3000...0x303F,      // CJK symbols and punctuation
        0x3040...0x30FF,      // Hiragana and Katakana
        0x3400...0x4DBF,      // CJK unified ideographs, extension A
        0x4E00...0x9FFF,      // CJK unified ideographs
        0xF900...0xFAFF,      // CJK compatibility ideographs
        0xFF01...0xFF60,      // Fullwidth forms
        0xFF66...0xFF9F,      // Halfwidth katakana
        0x20000...0x2A6DF     // CJK unified ideographs, extension B
    ]
}
