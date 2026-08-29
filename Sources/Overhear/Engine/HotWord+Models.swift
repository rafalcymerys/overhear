import Foundation

extension HotWord {
    /// Where to load this word's model from.
    ///
    /// Custom words already carry an absolute path — that is what
    /// `HotWordService` stores. Built-in words are held by name so the stored
    /// setting stays readable and stable, and resolve to the copy downloaded
    /// into the models directory on first launch.
    ///
    /// The directory is a parameter rather than always `modelsDirectory` so
    /// that a caller working against a different one — a test, chiefly —
    /// resolves the word model and the shared feature models from the same
    /// place. Splitting those two apart loads a word head that cannot find its
    /// own feature models.
    func modelPath(in directory: URL = HotWord.modelsDirectory) -> String {
        if isCustom { return modelValue }
        return directory.appendingPathComponent("\(modelValue).onnx").path
    }
}
