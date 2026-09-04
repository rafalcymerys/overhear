import Foundation

/// The third-party license notice bundled with the app.
///
/// The text is generated at build time by the GenerateAcknowledgements plugin
/// from the packages Overhear actually resolves, so there is nothing to keep in
/// step by hand here — see `Resources/acknowledgements.json` for which packages
/// it covers and why.
enum Acknowledgements {
    /// The notice, or nil if the generated resource is missing.
    ///
    /// Missing shouldn't happen: the plugin runs on every build, and the
    /// resource bundle it produces is one of the ones `scripts/build.sh` copies
    /// into the app. It is still worth reading as an optional rather than
    /// force-unwrapping — a missing license file should not be the thing that
    /// crashes a dictation app.
    static func text() -> String? {
        guard let url = Bundle.module.url(forResource: "Acknowledgements", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return text
    }
}
