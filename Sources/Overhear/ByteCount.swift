import Foundation

/// Sizes as the app writes them everywhere: a download that has just started is
/// "0 KB", not the "Zero KB" the formatter reaches for by default in the middle
/// of a sentence.
///
/// Free-standing rather than a method on `Int64`, and in one place rather than
/// three: every size in the interface is written inside a sentence — a model's
/// cost, what a removal frees, how far a download has got — and the three panes
/// that write one each had a private copy of this to call.
func byteCount(_ bytes: Int64) -> String {
    formatter.string(fromByteCount: bytes)
}

private let formatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowsNonnumericFormatting = false
    return formatter
}()
