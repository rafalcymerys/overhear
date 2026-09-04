import AppKit
import XCTest
@testable import Overhear

/// Overhear distributes a binary, and MIT and Apache-2.0 §4 both require the
/// license text to travel with it. These tests guard the two ways that can
/// quietly stop being true: the notice going missing from the bundle, and a
/// dependency being added without anyone deciding whether it ships.
@MainActor
final class AcknowledgementsTests: XCTestCase {
    func testNoticeIsBundled() throws {
        let text = try XCTUnwrap(Acknowledgements.text(),
                                 "The generated notice is missing from the bundle")
        XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Every package the manifest says ships has to actually appear, with its
    /// license text under it — an entry that generates an empty section is the
    /// failure this whole mechanism exists to prevent.
    func testEveryShippingPackageAppearsWithItsLicense() throws {
        let text = try XCTUnwrap(Acknowledgements.text())

        for (identity, entry) in try manifest() where entry.ships {
            XCTAssertTrue(text.contains(entry.name),
                          "\(identity) is marked as shipping but is not in the notice")
        }

        // The two Apache NOTICE files say things their LICENSE does not —
        // swift-crypto's records vendored SwiftNIO and wycheproof derivations —
        // so §4(d) wants them carried too.
        XCTAssertTrue(text.contains("NOTICE.txt"),
                      "NOTICE files are not being picked up alongside licenses")
        XCTAssertTrue(text.contains("Apache License"))
        XCTAssertTrue(text.contains("MIT License"))
    }

    /// Credit for the Parakeet weights is the whole of what CC BY 4.0 asks, and
    /// the models are the part of Overhear a reader is least likely to think of
    /// as third-party.
    func testCreditsTheModels() throws {
        let text = try XCTUnwrap(Acknowledgements.text())
        XCTAssertTrue(text.contains("NVIDIA"), "Parakeet's CC BY 4.0 credit is missing")
        XCTAssertTrue(text.contains("CC BY-NC-SA 4.0"), "openWakeWord's terms are missing")
    }

    /// The build plugin fails the build on an unclassified package, but only
    /// once someone builds the app. This says the same thing from `swift test`,
    /// which is what runs on a pull request.
    func testEveryResolvedPackageIsClassified() throws {
        let classified = Set(try manifest().keys)
        let resolved = try resolvedIdentities()

        XCTAssertEqual(resolved.subtracting(classified), [],
                       "resolved but unclassified in Resources/acknowledgements.json")
        XCTAssertEqual(classified.subtracting(resolved), [],
                       "classified in Resources/acknowledgements.json but no longer resolved")
    }

    // MARK: - Reading the project

    private struct Entry: Decodable {
        let name: String
        let ships: Bool
    }

    private struct Manifest: Decodable {
        let packages: [String: Entry]
    }

    /// The project root, reached from this file rather than from a bundle —
    /// `Package.resolved` and the manifest are project files, not resources.
    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func manifest() throws -> [String: Entry] {
        let url = projectRoot.appendingPathComponent("Resources/acknowledgements.json")
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)).packages
    }

    private func resolvedIdentities() throws -> Set<String> {
        let url = projectRoot.appendingPathComponent("Package.resolved")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let pins = (json as? [String: Any])?["pins"] as? [[String: Any]] ?? []
        let identities = pins.compactMap { $0["identity"] as? String }

        XCTAssertFalse(identities.isEmpty, "Package.resolved parsed to no pins at all")
        return Set(identities)
    }
}

/// The About window is the only way into the notice, so a button that opens
/// nothing would leave the licenses shipped but unreachable.
@MainActor
final class AboutWindowTests: XCTestCase {
    func testShowsNameAndVersion() {
        let info = AppInfo.current
        XCTAssertEqual(info.name, "Overhear")
        XCTAssertFalse(info.version.isEmpty, "no version to show in the About window")
        XCTAssertTrue(info.copyright.contains("Rafal Cymerys"))
    }

    func testOpensAndCloses() throws {
        let controller = AboutWindowController()
        controller.show()
        defer { controller.close() }

        XCTAssertNotNil(controller.window)
    }

    func testAcknowledgementsWindowCarriesTheNotice() throws {
        let controller = AcknowledgementsWindowController()
        controller.show()
        defer { controller.close() }

        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.title, "Acknowledgements")

        let scrollView = try XCTUnwrap(window.contentView as? NSScrollView)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)
        XCTAssertTrue(textView.string.contains("Apache License"),
                      "the window opened without the license text in it")
        XCTAssertFalse(textView.isEditable)
    }
}
