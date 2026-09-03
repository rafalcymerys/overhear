import Foundation

extension ByteCountFormatter {
    /// Sizes as the app writes them everywhere: a download that has just
    /// started is "0 KB", not the "Zero KB" the formatter reaches for by
    /// default in the middle of a sentence.
    static let overhear: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}
