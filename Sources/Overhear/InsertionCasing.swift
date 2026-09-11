import Foundation

/// Cases the front of an insertion to suit the sentence it is joining.
///
/// A transcription arrives as a sentence — capital at the front, full stop at
/// the end — which is right in an empty field and wrong the moment it lands
/// halfway through something already being written, where a capital mid-line
/// reads as a mistake rather than as speech.
///
/// Two questions, asked separately. Which character to change, which is a
/// question about the insertion; and which way to change it, which is a
/// question about the field. Neither knows about the other, and the second is
/// read backwards from the caret because what decides is rarely the character
/// the insertion touches: a sentence that ended inside quotation marks has a
/// bracket or two and a space between its full stop and the caret.
/// `Specs/Casing.md`.
enum InsertionCasing {
    static func apply(to text: String, in context: CaretContext) -> String {
        guard let index = characterToCase(in: text) else { return text }
        guard !spellsItself(text, from: index) else { return text }

        let character = text[index]
        let recased = beginsASentence(context.before)
            ? character.uppercased()
            : character.lowercased()

        return text.replacingCharacters(in: index...index, with: recased)
    }

    /// The character the rule will change, or `nil` when the insertion has
    /// none to offer.
    ///
    /// Leading whitespace and anything that opens — a bracket, a quote, the
    /// Spanish marks — are stepped over, so the capital lands on the letter
    /// rather than on the punctuation in front of it. The step stops at the
    /// first character that is neither, and the rule applies only if that
    /// character is a letter: an insertion leading with a digit or a symbol is
    /// left alone rather than hunted through for something to capitalise, or
    /// `1999 was a good year` comes back as `1999 Was a good year`.
    private static func characterToCase(in text: String) -> String.Index? {
        for index in text.indices {
            let character = text[index]
            if character.isWhitespace || opening.contains(character) { continue }
            return character.isLetter ? index : nil
        }
        return nil
    }

    /// Whether the caret sits where a sentence begins.
    ///
    /// Running out of text to read is an answer rather than a failure: nothing
    /// before the caret is the start of the field, and a run of nothing but
    /// spaces and brackets before that is a line that has not started its
    /// sentence yet.
    private static func beginsASentence(_ before: String) -> Bool {
        for character in before.reversed() {
            // Decisive rather than skippable, though it is whitespace: a line
            // break is how someone writes a new paragraph, a new list item or a
            // new cell, and none of those continue the sentence above them.
            if character.isNewline { return true }
            if character.isWhitespace { continue }
            if transparent.contains(character) { continue }
            return boundary.contains(character)
        }
        return true
    }

    /// Characters that take what follows them without a gap, and so are read
    /// past when looking for the letter to case.
    private static let opening: Set<Character> = [
        "(", "[", "{", "\"", "'", "\u{201C}", "\u{2018}", "¿", "¡"
    ]

    /// Characters a sentence begins after.
    ///
    /// The enders, in the ordinary and the fullwidth forms; the Spanish marks,
    /// which open the sentence they mark rather than sitting inside one; and a
    /// double quotation mark, which starts the speech it introduces.
    ///
    /// The straight `"` is ambiguous — nothing in the field says which end of a
    /// pair it is — and it is read as a boundary either way, because both
    /// readings want a capital after it. `He said "` opens a quotation, and
    /// `He said "Hello." ` has a full stop one step further back.
    private static let boundary: Set<Character> = [
        ".", "!", "?", "\u{2026}",
        "\u{3002}", "\u{FF01}", "\u{FF1F}",
        "¿", "¡",
        "\"", "\u{201C}"
    ]

    /// Punctuation that says nothing either way, and is read past to reach
    /// something that does.
    ///
    /// A sentence can end behind its closing brackets, so they are transparent
    /// rather than mid-sentence. So are the opening brackets, from the other
    /// direction: `The fox jumps (` is a parenthetical inside a sentence and
    /// `The fox jumps. (` starts a new one, and only what precedes the bracket
    /// tells them apart. The single quotes are here rather than among the
    /// boundaries because they are apostrophes more often than quotation marks
    /// — `the dogs' ` continues its sentence.
    private static let transparent: Set<Character> = [
        ")", "]", "}", "\u{201D}", "'", "\u{2019}",
        "(", "[", "{"
    ]

    /// Whether the word the rule landed on carries its own capitals.
    ///
    /// One test covers two of the three cases: a capital anywhere but the front
    /// means the word spells itself — `NASA`, `iPhone`, `McDonald` — and
    /// re-casing the first letter would damage it whichever way the sentence
    /// wanted it. The English `I` has to be asked for separately, having no
    /// second letter to give it away.
    private static func spellsItself(_ text: String, from index: String.Index) -> Bool {
        let word = text[index...].prefix { $0.isLetter || $0 == "'" || $0 == "\u{2019}" }
        if word.dropFirst().contains(where: \.isUppercase) { return true }
        return isEnglishI(word)
    }

    /// `I`, and the contractions that are the pronoun with something attached.
    /// `It` is not one of them.
    private static func isEnglishI(_ word: Substring) -> Bool {
        guard word.first == "I" else { return false }
        let rest = word.dropFirst()
        return rest.isEmpty || rest.first == "'" || rest.first == "\u{2019}"
    }
}
