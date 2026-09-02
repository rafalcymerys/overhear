import XCTest
@testable import Overhear

@MainActor
final class SettingsTests: OverhearTestCase {

    // B21 — defaults

    func testDefaultsWithEmptyStorage() {
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)

        XCTAssertEqual(settings.selectedLanguageCodes, ["en", "pl"])
        XCTAssertTrue(settings.showOverlay)
        XCTAssertTrue(settings.dictateOnLaunch)
        XCTAssertTrue(settings.stripAnnotations, "annotations are filtered unless the user opts out")
        XCTAssertFalse(settings.translateUnsupported, "translation is a choice, not something that happens by accident")
        XCTAssertEqual(settings.cancelWord, HotWord.defaultWord)
    }

    func testTranslateUnsupportedRoundTripsWhenTurnedOn() {
        let defaults = makeDefaults()
        AppSettings(defaults: defaults, availableHotWords: HotWord.builtIn).translateUnsupported = true

        let reloaded = AppSettings(defaults: defaults, availableHotWords: HotWord.builtIn)
        XCTAssertTrue(reloaded.translateUnsupported)
    }

    /// Off has to survive a relaunch, which a plain `bool(forKey:)` read would
    /// get wrong — it returns false for both "off" and "never set".
    func testStripAnnotationsRoundTripsWhenTurnedOff() {
        let defaults = makeDefaults()
        AppSettings(defaults: defaults, availableHotWords: HotWord.builtIn).stripAnnotations = false

        let reloaded = AppSettings(defaults: defaults, availableHotWords: HotWord.builtIn)
        XCTAssertFalse(reloaded.stripAnnotations)
    }

    func testDefaultCancelWordIsAlexa() {
        XCTAssertEqual(HotWord.defaultWord.modelValue, "alexa")
    }

    // B21 — persistence

    func testSettingsRoundTripThroughStorage() {
        let defaults = makeDefaults()

        let first = AppSettings(defaults: defaults, availableHotWords: HotWord.builtIn)
        first.selectedLanguageCodes = ["fr", "de"]
        first.showOverlay = false
        first.dictateOnLaunch = false
        // Deliberately not the default word — otherwise a failure to persist
        // would look identical to the fallback.
        first.cancelWord = HotWord.builtIn[1]

        let second = AppSettings(defaults: defaults, availableHotWords: HotWord.builtIn)

        XCTAssertEqual(second.selectedLanguageCodes, ["fr", "de"])
        XCTAssertFalse(second.showOverlay)
        XCTAssertFalse(second.dictateOnLaunch)
        XCTAssertEqual(second.cancelWord, HotWord.builtIn[1])
    }

    func testTogglesPersistFalseRatherThanFallingBackToDefault() {
        let defaults = makeDefaults()

        let first = AppSettings(defaults: defaults, availableHotWords: HotWord.builtIn)
        first.showOverlay = false
        first.dictateOnLaunch = false

        // Both default to true, so a naive `bool(forKey:)` read of a missing key
        // is indistinguishable from a stored false. The object(forKey:) check is
        // what makes this work.
        let second = AppSettings(defaults: defaults, availableHotWords: HotWord.builtIn)
        XCTAssertFalse(second.showOverlay)
        XCTAssertFalse(second.dictateOnLaunch)
    }

    // B21 — the dangerous edge: a persisted custom word whose file is gone

    func testMissingCustomCancelWordFallsBackToDefault() {
        let defaults = makeDefaults()
        let custom = HotWord.custom(path: tempDirectory.appendingPathComponent("gone.onnx").path,
                                    name: "Gone")

        let first = AppSettings(defaults: defaults, availableHotWords: HotWord.builtIn + [custom])
        first.cancelWord = custom
        XCTAssertEqual(first.cancelWord, custom)

        // The model file has since been deleted, so it is no longer on offer.
        let second = AppSettings(defaults: defaults, availableHotWords: HotWord.builtIn)

        XCTAssertEqual(second.cancelWord, HotWord.defaultWord,
                       "a dead model path would make the engine exit 1 on launch")
    }

    func testCustomCancelWordIsRestoredWhenStillInstalled() {
        let defaults = makeDefaults()
        let custom = HotWord.custom(path: tempDirectory.appendingPathComponent("mine.onnx").path,
                                    name: "Mine")

        let first = AppSettings(defaults: defaults, availableHotWords: HotWord.builtIn + [custom])
        first.cancelWord = custom

        let second = AppSettings(defaults: defaults, availableHotWords: HotWord.builtIn + [custom])
        XCTAssertEqual(second.cancelWord, custom)
    }

    // Language catalog invariants the settings UI relies on

    func testLanguageCatalogHasNoDuplicateCodes() {
        let codes = RecognitionLanguage.all.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    func testSelectedLanguagesResolveAgainstTheCatalog() {
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        settings.selectedLanguageCodes = ["pl", "en", "not-a-language"]

        XCTAssertEqual(Set(settings.selectedLanguages.map(\.code)), ["en", "pl"])
    }

    // MARK: - The active model and the languages it constrains

    func testDefaultActiveModelIsWhisperBase() {
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        XCTAssertEqual(settings.activeModelID, ModelCatalog.whisperBase.id)
        XCTAssertEqual(settings.activeModel, ModelCatalog.whisperBase)
    }

    func testActiveModelRoundTripsThroughStorage() {
        let defaults = makeDefaults()
        AppSettings(defaults: defaults, availableHotWords: HotWord.builtIn)
            .activeModelID = ModelCatalog.whisperSmall.id

        let reloaded = AppSettings(defaults: defaults, availableHotWords: HotWord.builtIn)
        XCTAssertEqual(reloaded.activeModel, ModelCatalog.whisperSmall)
    }

    /// A stored id for a model that no longer exists must not leave the app with
    /// nothing to transcribe with.
    func testAnUnknownStoredModelFallsBackToTheDefault() {
        let defaults = makeDefaults()
        defaults.set("whisper-from-a-later-version", forKey: "activeTranscriptionModel")

        let settings = AppSettings(defaults: defaults, availableHotWords: HotWord.builtIn)
        XCTAssertEqual(settings.activeModel, ModelCatalog.defaultModel)
    }

    /// A multilingual model uses the selection as it stands.
    func testEverySelectedLanguageIsUsedByAMultilingualModel() {
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        settings.selectedLanguageCodes = ["en", "pl"]

        XCTAssertEqual(settings.effectiveLanguageCodes, ["en", "pl"])
        XCTAssertTrue(settings.unsupportedSelectedLanguages.isEmpty)
    }

    /// Activating an English-only model narrows what is in use — and says which
    /// language it dropped, rather than silently transcribing Polish as English.
    func testAnEnglishOnlyModelNarrowsTheLanguagesInUse() {
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        settings.selectedLanguageCodes = ["en", "pl"]
        settings.activeModelID = ModelCatalog.whisperBaseEnglish.id

        XCTAssertEqual(settings.effectiveLanguageCodes, ["en"])
        XCTAssertEqual(settings.unsupportedSelectedLanguages.map(\.code), ["pl"])
    }

    /// The selection itself is never edited, so going back to a multilingual
    /// model brings the language back without the user reselecting it.
    func testTheNarrowedLanguageComesBackWithAMultilingualModel() {
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        settings.selectedLanguageCodes = ["en", "pl"]
        settings.activeModelID = ModelCatalog.whisperBaseEnglish.id
        XCTAssertEqual(settings.effectiveLanguageCodes, ["en"])

        settings.activeModelID = ModelCatalog.whisperBase.id

        XCTAssertEqual(settings.selectedLanguageCodes, ["en", "pl"], "the stored selection was never edited")
        XCTAssertEqual(settings.effectiveLanguageCodes, ["en", "pl"])
    }

    /// The narrowing is not Whisper's alone — Parakeet's English-only build
    /// constrains the selection the same way.
    func testAnEnglishOnlyParakeetModelNarrowsTheLanguagesToo() {
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        settings.selectedLanguageCodes = ["en", "pl"]
        settings.activeModelID = ModelCatalog.parakeetV2.id

        XCTAssertEqual(settings.effectiveLanguageCodes, ["en"])
        XCTAssertEqual(settings.unsupportedSelectedLanguages.map(\.code), ["pl"])

        settings.activeModelID = ModelCatalog.parakeetV3.id
        XCTAssertEqual(settings.effectiveLanguageCodes, ["en", "pl"], "v3 speaks both")
    }

    /// Only Whisper can translate, and the General pane keys the row off this.
    func testOnlyWhisperReportsThatItCanTranslate() {
        XCTAssertTrue(TranscriptionEngineKind.whisper.canTranslate)
        XCTAssertFalse(TranscriptionEngineKind.parakeet.canTranslate)
    }

    /// Selecting only languages the model cannot do must still leave the engine
    /// something to decode with.
    func testAModelWithNoSelectedLanguageInCommonFallsBackToOneItSupports() {
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        settings.selectedLanguageCodes = ["pl", "de"]
        settings.activeModelID = ModelCatalog.whisperBaseEnglish.id

        XCTAssertEqual(settings.effectiveLanguageCodes, ["en"])
    }

}
