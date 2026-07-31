import CryptoKit
import Foundation

/// Builds the Python environment the engine needs, by running `install.sh`.
///
/// The app ships the script inside its bundle and runs it on first launch, so a
/// fresh Mac only has to unzip the app and open it. Progress lines the script
/// marks with ">>> " are surfaced in the setup window; the full output goes to
/// a log next to the environment.
@MainActor
final class EngineInstaller: ObservableObject {
    /// Where everything lives. Injected so tests can drive a fake script in a
    /// temporary directory instead of touching the real environment.
    struct Environment {
        var script: URL
        var requirements: URL
        var python: String
        var venvDirectory: URL
        var logFile: URL
    }

    enum Decision: Equatable {
        case ready
        case install(Reason)
    }

    /// Why setup has to run — the setup window says so, because a returning
    /// user seeing it again deserves an explanation.
    enum Reason: String {
        case firstLaunch
        case interrupted
        case dependenciesChanged

        var explanation: String {
            switch self {
            case .firstLaunch:
                return "Installing the speech engine and downloading its models. This happens once and can take a few minutes."
            case .interrupted:
                return "The previous setup didn't finish, so Overhear is installing the speech engine again. This can take a few minutes."
            case .dependenciesChanged:
                return "Overhear's dependencies changed, so it is updating the speech engine. This can take a few minutes."
            }
        }
    }

    enum InstallError: LocalizedError, Equatable {
        case scriptNotFound
        case requirementsNotFound
        case pythonNotFound
        case failed(status: Int32, output: String)

        var errorDescription: String? {
            switch self {
            case .scriptNotFound:
                return "Could not find install.sh in the app bundle"
            case .requirementsNotFound:
                return "Could not find requirements.txt in the app bundle"
            case .pythonNotFound:
                return "Python 3 not found. Install it with: brew install python3"
            case let .failed(status, output):
                let detail = output.isEmpty ? "" : "\n\n\(output)"
                return "Setup failed (exit code \(status))." + detail
            }
        }
    }

    @Published private(set) var step: String = ""
    @Published private(set) var isInstalling = false
    @Published private(set) var failure: String?
    @Published private(set) var reason: Reason = .firstLaunch

    /// The environment the app manages itself. A source checkout keeps its own
    /// `.venv` next to the sources instead; see `decide(…)`.
    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Overhear")
    }

    static var managedVenvDirectory: URL {
        supportDirectory.appendingPathComponent(".venv")
    }

    static var managedVenvPython: String {
        managedVenvDirectory.appendingPathComponent("bin/python3").path
    }

    static func stampFile(inVenv venv: URL) -> URL {
        venv.appendingPathComponent(".overhear-requirements")
    }

    // MARK: - Deciding whether to install

    /// Whether the Python environment still has to be built.
    ///
    /// A venv that isn't the one we manage belongs to a source checkout — the
    /// developer owns it, so leave it alone. For our own venv the stamp records
    /// which requirements it was built from, so a dependency bump reinstalls
    /// and an interrupted install (venv but no stamp) is retried.
    static func decide(existingVenvPython: String?,
                       managedVenvPython: String,
                       managedStamp: String?,
                       requirementsDigest: String) -> Decision {
        guard let existingVenvPython else {
            return .install(.firstLaunch)
        }
        guard existingVenvPython == managedVenvPython else {
            return .ready
        }
        guard let managedStamp else {
            return .install(.interrupted)
        }
        return managedStamp == requirementsDigest ? .ready : .install(.dependenciesChanged)
    }

    /// The decision for the real environment. Any probing failure (missing
    /// requirements, unreadable stamp) resolves to "install" — running setup
    /// again is cheap when everything is already in place.
    static func decideForCurrentEnvironment() -> Decision {
        guard let requirements = findRequirementsPath(),
              let digest = try? digest(ofFileAt: URL(fileURLWithPath: requirements)) else {
            return .install(.firstLaunch)
        }
        return decide(
            existingVenvPython: existingVenvPython(),
            managedVenvPython: managedVenvPython,
            managedStamp: readStamp(inVenv: managedVenvDirectory),
            requirementsDigest: digest
        )
    }

    /// The first venv interpreter that exists, in the same order the engine
    /// would pick one. System interpreters are ignored: they can run Python but
    /// never have the engine's dependencies.
    static func existingVenvPython() -> String? {
        let candidates = EngineProcess.pythonCandidates(
            enginePath: EngineProcess.findEnginePath(),
            resourcePath: Bundle.main.resourcePath,
            bundlePath: Bundle.main.bundlePath,
            home: FileManager.default.homeDirectoryForCurrentUser
        )
        return candidates
            .filter { $0.contains("/.venv/") }
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    static func readStamp(inVenv venv: URL) -> String? {
        guard let contents = try? String(contentsOf: stampFile(inVenv: venv), encoding: .utf8) else {
            return nil
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Hex SHA-256 of a file's contents, matching what `shasum -a 256` prints —
    /// that is what install.sh writes into the stamp.
    static func digest(ofFileAt url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Locating the pieces

    static func resolveEnvironment() throws -> Environment {
        guard let script = findScriptPath() else { throw InstallError.scriptNotFound }
        guard let requirements = findRequirementsPath() else { throw InstallError.requirementsNotFound }
        guard let python = findInstallerPython() else { throw InstallError.pythonNotFound }

        return Environment(
            script: URL(fileURLWithPath: script),
            requirements: URL(fileURLWithPath: requirements),
            python: python,
            venvDirectory: managedVenvDirectory,
            logFile: supportDirectory.appendingPathComponent("install.log")
        )
    }

    private static func findScriptPath() -> String? {
        firstExisting([
            Bundle.main.path(forResource: "install", ofType: "sh"),
            Bundle.main.resourcePath.map { "\($0)/install.sh" },
            sourceCheckoutPath("scripts/install.sh"),
        ])
    }

    private static func findRequirementsPath() -> String? {
        firstExisting([
            Bundle.main.path(forResource: "requirements", ofType: "txt", inDirectory: "Engine"),
            Bundle.main.resourcePath.map { "\($0)/Engine/requirements.txt" },
            sourceCheckoutPath("Engine/requirements.txt"),
        ])
    }

    /// A Python that can *create* the environment — unlike the engine, which
    /// needs the venv interpreter, any working system Python 3 will do.
    private static func findInstallerPython() -> String? {
        for candidate in EngineProcess.systemPythonCandidates
        where FileManager.default.isExecutableFile(atPath: candidate) && runs(candidate) {
            return candidate
        }
        return nil
    }

    /// `/usr/bin/python3` exists on a stock Mac as a Command Line Tools stub
    /// that fails until the tools are installed, so existence isn't enough.
    private static func runs(_ python: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments = ["--version"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }

    private static func sourceCheckoutPath(_ relative: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Overhear
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent(relative)
            .path
    }

    private static func firstExisting(_ candidates: [String?]) -> String? {
        candidates
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - Running the installer

    /// Put the published state in its starting shape, so the setup window opens
    /// with the right explanation and no leftover failure from a previous try.
    func prepare(reason: Reason) {
        self.reason = reason
        failure = nil
        step = "Preparing…"
    }

    func install(using environment: Environment, reason: Reason = .firstLaunch) async throws {
        prepare(reason: reason)
        isInstalling = true
        defer { isInstalling = false }

        do {
            try await run(environment)
        } catch {
            failure = error.localizedDescription
            throw error
        }
    }

    private func run(_ environment: Environment) async throws {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: environment.logFile.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
        fileManager.createFile(atPath: environment.logFile.path, contents: nil)
        let log = try? FileHandle(forWritingTo: environment.logFile)
        defer { try? log?.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            environment.script.path,
            "--venv", environment.venvDirectory.path,
            "--requirements", environment.requirements.path,
            "--python", environment.python,
        ]
        // Launched from Finder the app inherits a bare environment; the script
        // only needs PATH for `shasum`/`awk`, which live in the default one.
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        let tail = TailBuffer()
        let status: Int32 = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [self] in
                // Drain first: the child exits only after its output is read,
                // and reading to EOF means the tail is complete by the time we
                // report a failure.
                drain(pipe: pipe, log: log, tail: tail)
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            }
        }

        guard status == 0 else {
            throw InstallError.failed(status: status, output: tail.text())
        }
        step = "Setup complete."
    }

    private nonisolated func drain(pipe: Pipe, log: FileHandle?, tail: TailBuffer) {
        let handle = pipe.fileHandleForReading
        var buffer = Data()

        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            try? log?.write(contentsOf: data)
            buffer.append(data)

            while let newlineRange = buffer.range(of: Data([UInt8(ascii: "\n")])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                guard let line = String(data: lineData, encoding: .utf8) else { continue }
                tail.record(line)

                if let message = Self.progressMessage(in: line) {
                    Task { @MainActor in
                        self.step = message
                    }
                }
            }
        }
    }

    /// The script's own progress markers. Anything else is pip/model noise that
    /// belongs in the log, not in front of the user.
    nonisolated static func progressMessage(in line: String) -> String? {
        guard line.hasPrefix(progressMarker) else { return nil }
        let message = line
            .dropFirst(progressMarker.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }
}

/// The prefix install.sh puts on the lines meant for the user.
private let progressMarker = ">>> "

/// Keeps the last few output lines, so a failure can be explained without
/// making the user open the log.
final class TailBuffer: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var lines: [String] = []

    init(limit: Int = 5) {
        self.limit = limit
    }

    func record(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        lines.append(trimmed)
        if lines.count > limit {
            lines.removeFirst(lines.count - limit)
        }
    }

    func text() -> String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}
