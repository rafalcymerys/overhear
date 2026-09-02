import Foundation
@testable import Overhear

/// A value a test shares with code running off the main actor — a flag a fake
/// downloader reads, or the list of models it was asked for.
final class TestBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            stored = newValue
        }
    }

    /// Change the value and read the result in one step, for a counter that
    /// several calls increment.
    @discardableResult
    func mutate<Result>(_ change: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return change(&stored)
    }
}
