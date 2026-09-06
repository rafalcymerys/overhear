import WhisperKit
import XCTest
@testable import Overhear

/// R-122. WhisperKit's initialiser decides whether to load the models with
/// `config.load ?? (config.modelFolder != nil)`, so a configuration that says
/// nothing about loading and names no model folder resolves to *don't*: the
/// initialiser returns having only located the weights on disk, and every
/// CoreML model then loads lazily inside the first transcription — the one
/// somebody is waiting on.
///
/// Cheap enough to run everywhere, unlike the rest of the Whisper suite: it
/// reads the configuration rather than acting on it.
final class WhisperConfigurationTests: XCTestCase {
    func testTheConfigurationLoadsTheModels() {
        for model in ModelCatalog.all where model.engine == .whisper {
            let config = WhisperTranscriber.configuration(for: model)
            XCTAssertTrue(
                config.load ?? (config.modelFolder != nil),
                "\(model.displayName): WhisperKit would return without loading, "
                    + "leaving the first transcription to do it"
            )
        }
    }

    /// The trap is that leaving `load` out reads as a default rather than as a
    /// decision. Asserting on it directly says which of the two ways of
    /// satisfying the rule above is the one in use.
    func testLoadingIsStatedRatherThanInferredFromAModelFolder() {
        let config = WhisperTranscriber.configuration(for: ModelCatalog.defaultModel)
        XCTAssertEqual(config.load, true, "loading has to be asked for, not left to the default")
    }
}
