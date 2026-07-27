import Foundation
import XCTest
@testable import Overhear

/// Records injections instead of touching the pasteboard or posting Cmd+V.
final class SpyInjector: TextInjecting, @unchecked Sendable {
    private(set) var injected: [String] = []

    func inject(text: String) {
        injected.append(text)
    }
}

/// Base class providing a per-test temporary directory and a throwaway
/// UserDefaults suite, so nothing leaks between tests or into the real app.
class OverhearTestCase: XCTestCase {
    private(set) var tempDirectory: URL!
    private(set) var defaultsSuiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("overhear-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defaultsSuiteName = "overhear.tests.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: defaultsSuiteName)!
    }
}

/// Poll until `condition` holds. Awaiting yields the main actor, which lets the
/// `Task { @MainActor }` hops that deliver engine events actually run.
@MainActor
func waitUntil(_ description: String,
               timeout: TimeInterval = 5.0,
               file: StaticString = #filePath,
               line: UInt = #line,
               condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("timed out waiting for \(description)", file: file, line: line)
}

/// Assert something stays false for a while — the counterpart to waitUntil.
@MainActor
func assertNever(_ description: String,
                 within: TimeInterval = 0.5,
                 file: StaticString = #filePath,
                 line: UInt = #line,
                 condition: () -> Bool) async {
    let deadline = Date().addingTimeInterval(within)
    while Date() < deadline {
        if condition() {
            XCTFail("unexpected \(description)", file: file, line: line)
            return
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
