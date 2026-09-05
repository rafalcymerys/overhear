import Foundation
import OnnxRuntimeBindings

/// The process's one ONNX Runtime environment.
///
/// ONNX Runtime allows a single default environment per process and throws when
/// asked for a second while the first is alive. Engines are built and thrown
/// away all the time — a language change, a model swap, a retry after a failed
/// load — so an environment per engine only works while their lifetimes never
/// touch, which is a timing assumption rather than a guarantee. Two engines
/// overlapping by a moment was enough to fail the retry that first launch
/// depends on.
///
/// Shared rather than made and released, because there is nothing to release:
/// one environment is what the library wants, and it costs nothing to keep for
/// the life of the app.
enum ORTEnvironment {
    /// Built once, on the first engine to ask. The failure is kept rather than
    /// retried — if the runtime cannot start there is nothing a second attempt
    /// would do differently, and the engine turns it into a message.
    private static let environment: Result<ORTEnv, Error> = Result {
        try ORTEnv(loggingLevel: .warning)
    }

    static func shared() throws -> ORTEnv {
        try environment.get()
    }
}
