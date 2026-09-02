import AppKit
import XCTest
@testable import Overhear

/// The settings window is the only place most of these preferences can be
/// changed, so a pane that fails to appear — or appears in a window sized for a
/// different one — is the whole feature broken.
@MainActor
final class SettingsWindowTests: XCTestCase {
    func testOffersGeneralTranscriptionAndHotWordsInThatOrder() {
        XCTAssertEqual(SettingsTab.allCases.map(\.title), ["General", "Transcription", "Hot Words"])
    }

    /// The language list moved into the Transcription pane, where it belongs to
    /// the model that constrains it. A pane of its own would be a second place
    /// to look for one setting.
    func testNoLanguagePaneRemains() {
        XCTAssertNil(SettingsTab(rawValue: "languages"))
        XCTAssertFalse(SettingsTab.allCases.map(\.title).contains("Languages"))
    }

    /// The toolbar identifies panes by their raw value, so two panes sharing one
    /// would make a tab unselectable.
    func testEachPaneHasItsOwnToolbarItem() {
        let identifiers = SettingsTab.allCases.map(\.itemIdentifier)
        XCTAssertEqual(Set(identifiers).count, SettingsTab.allCases.count)

        for tab in SettingsTab.allCases {
            XCTAssertEqual(SettingsTab(rawValue: tab.itemIdentifier.rawValue), tab)
            XCTAssertNotNil(
                NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil),
                "\(tab.title) has no symbol, so its toolbar item would be blank"
            )
        }
    }

    func testOpensOnGeneral() throws {
        let controller = SettingsWindowController()
        controller.show()
        defer { controller.close() }

        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(controller.selected, .general)
        XCTAssertEqual(window.title, "General")
    }

    /// Every pane needs a toolbar item, and all of them have to be selectable —
    /// a non-selectable item behaves as a button and never stays highlighted.
    func testToolbarCarriesEveryPaneAsASelectableItem() throws {
        let controller = SettingsWindowController()
        controller.show()
        defer { controller.close() }

        let toolbar = try XCTUnwrap(controller.window?.toolbar)
        let expected = SettingsTab.allCases.map(\.itemIdentifier)

        XCTAssertEqual(controller.toolbarDefaultItemIdentifiers(toolbar), expected)
        XCTAssertEqual(controller.toolbarSelectableItemIdentifiers(toolbar), expected)
        XCTAssertEqual(toolbar.selectedItemIdentifier, SettingsTab.general.itemIdentifier)

        for tab in SettingsTab.allCases {
            let item = controller.toolbar(toolbar, itemForItemIdentifier: tab.itemIdentifier, willBeInsertedIntoToolbar: true)
            XCTAssertEqual(item?.label, tab.title)
            XCTAssertNotNil(item?.image, "\(tab.title) would show an empty toolbar item")
        }
    }

    func testSelectingAPaneRetitlesTheWindow() throws {
        let controller = SettingsWindowController()
        controller.show()
        defer { controller.close() }

        controller.select(.transcription)
        XCTAssertEqual(controller.selected, .transcription)
        XCTAssertEqual(controller.window?.title, "Transcription")

        controller.select(.hotWords)
        XCTAssertEqual(controller.window?.title, "Hot Words")
    }

    /// The point of the tabs: each pane gets a window its own size, rather than
    /// every pane sharing one sized for the largest.
    func testEachPaneResizesTheWindowToItself() async throws {
        let controller = SettingsWindowController()
        controller.show()
        defer { controller.close() }

        let window = try XCTUnwrap(controller.window)
        var heights: [SettingsTab: CGFloat] = [:]

        for tab in SettingsTab.allCases {
            controller.select(tab)
            let expected = expectedContentHeight(of: tab)
            // The resize is animated, so settle rather than assert immediately.
            await waitUntil("the window resizes for \(tab.title)") {
                abs(window.contentLayoutRect.height - expected) < 2
            }
            heights[tab] = expected
        }

        XCTAssertEqual(Set(heights.values).count, SettingsTab.allCases.count,
                       "panes should not all end up the same height")
        let general = try XCTUnwrap(heights[.general])
        let transcription = try XCTUnwrap(heights[.transcription])
        XCTAssertLessThan(general, transcription,
                          "General holds two toggles; Transcription holds the active model and the catalogue")
    }

    /// Selecting the pane that is already showing must not restart the resize —
    /// clicking the current tab should do nothing at all.
    func testReselectingTheCurrentPaneIsANoOp() throws {
        let controller = SettingsWindowController()
        controller.show()
        defer { controller.close() }

        let window = try XCTUnwrap(controller.window)
        let before = window.frame
        controller.select(.general)
        XCTAssertEqual(window.frame, before)
    }

    // MARK: - Sizing

    /// Panes are as tall as their content, so the window has no dead space.
    func testPanesSizeToTheirContent() {
        for tab in SettingsTab.allCases {
            let view = tab.makeContentView()
            let size = tab.contentSize(of: view)
            XCTAssertEqual(size.width, SettingsTab.width)
            XCTAssertGreaterThan(size.height, 0)
            XCTAssertLessThan(size.height, tab.maximumHeight,
                              "\(tab.title) fits its content and should not be capped")
        }
    }

    private func expectedContentHeight(of tab: SettingsTab) -> CGFloat {
        tab.contentSize(of: tab.makeContentView()).height
    }
}
