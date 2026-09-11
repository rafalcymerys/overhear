import Foundation

/// What sits either side of the point text is about to be inserted at.
///
/// The two sides are not shaped alike, because the two rules that read them do
/// not ask alike. Spacing wants the single character the insertion meets;
/// casing has to look past a run of spaces and closing brackets to reach the
/// punctuation that ended the last sentence. So the text before the caret is a
/// run and the character after it is one character — nothing asks the other
/// side for more.
///
/// An empty `before` covers two cases that the rules do not have to tell
/// apart: the caret is at the start of the field, or the field is one whose
/// contents Overhear cannot read. Neither has a sentence to continue and
/// neither has a character to space against.
struct CaretContext: Equatable {
    /// The text immediately before the caret, ending at it, or as much of it
    /// as the field would hand over.
    var before: String

    /// The character immediately after the caret.
    var after: Character?

    /// The character the insertion meets on the way in.
    var characterBefore: Character? { before.last }

    /// A field that said nothing about itself. Text goes in as transcribed,
    /// save for the capital casing falls back to.
    static let unknown = CaretContext(before: "", after: nil)
}
