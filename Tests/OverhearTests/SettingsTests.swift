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
        XCTAssertEqual(settings.cancelWord, HotWord.defaultWord)
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
        let codes = WhisperLanguage.all.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count)
    }

    func testSelectedLanguagesResolveAgainstTheCatalog() {
        let settings = AppSettings(defaults: makeDefaults(), availableHotWords: HotWord.builtIn)
        settings.selectedLanguageCodes = ["pl", "en", "not-a-language"]

        XCTAssertEqual(Set(settings.selectedLanguages.map(\.code)), ["en", "pl"])
    }
}
