import Foundation

/// Finding the pieces setup runs with: the script and requirements the app
/// ships, and a Python to build the environment with.
///
/// A stock Mac has no usable Python until the Xcode command line tools are
/// installed, and that install happens in the system's own window — so this is
/// also where the installer waits for it to finish.
extension EngineInstaller {
    /// Probing runs a candidate interpreter, and the Command Line Tools stub
    /// takes as long as the system dialog is up — so run it off the main actor,
    /// where it cannot freeze the setup window.
    static func probeOffMainActor(_ probe: @escaping @Sendable (Bool) -> String?,
                                  mayRequestDeveloperTools: Bool) async -> String? {
        await Task.detached(priority: .userInitiated) {
            probe(mayRequestDeveloperTools)
        }.value
    }

    static func findScriptPath() -> String? {
        firstExisting([
            Bundle.main.path(forResource: "install", ofType: "sh"),
            Bundle.main.resourcePath.map { "\($0)/install.sh" },
            sourceCheckoutPath("scripts/install.sh"),
        ])
    }

    static func findRequirementsPath() -> String? {
        firstExisting([
            Bundle.main.path(forResource: "requirements", ofType: "txt", inDirectory: "Engine"),
            Bundle.main.resourcePath.map { "\($0)/Engine/requirements.txt" },
            sourceCheckoutPath("Engine/requirements.txt"),
        ])
    }

    /// A Python that can *create* the environment — unlike the engine, which
    /// needs the venv interpreter, any working system Python 3 will do.
    ///
    /// Running the stub is what asks macOS to install the Command Line Tools.
    /// That belongs on the first try only, so once the request is out,
    /// `mayRequestDeveloperTools` is false and the stub is judged by whether
    /// the tools have arrived instead of by running it again.
    nonisolated static func findInstallerPython(mayRequestDeveloperTools: Bool) -> String? {
        let toolsInstalled = developerToolsInstalled()
        for candidate in EngineProcess.systemPythonCandidates
        where mayProbe(candidate, mayRequestDeveloperTools: mayRequestDeveloperTools, developerToolsInstalled: toolsInstalled) {
            if FileManager.default.isExecutableFile(atPath: candidate), runs(candidate) {
                return candidate
            }
        }
        return nil
    }

    /// Whether running this candidate is worth it right now. Only the stub is
    /// ever held back: running it is the request for the developer tools, so
    /// once that request is out it has nothing to offer until they arrive.
    nonisolated static func mayProbe(_ candidate: String,
                                     mayRequestDeveloperTools: Bool,
                                     developerToolsInstalled: Bool) -> Bool {
        candidate != developerToolsStub || mayRequestDeveloperTools || developerToolsInstalled
    }

    /// Whether the stub has a real interpreter to forward to. The stub itself
    /// is always on disk, so only the tools' own python3 answers this.
    nonisolated static func developerToolsInstalled() -> Bool {
        developerToolsPythons.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// `/usr/bin/python3` exists on a stock Mac as a Command Line Tools stub
    /// that fails until the tools are installed, so existence isn't enough.
    nonisolated static func runs(_ python: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: python)
        proc.arguments = ["--version"]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return false }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }

    static func sourceCheckoutPath(_ relative: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Overhear
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent(relative)
            .path
    }

    static func firstExisting(_ candidates: [String?]) -> String? {
        candidates
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0) }
    }
}

/// The Command Line Tools stub. It ships with macOS, so finding it on disk says
/// nothing about whether the tools behind it are installed.
private let developerToolsStub = "/usr/bin/python3"

/// Where the developer tools keep the real interpreter the stub forwards to.
private let developerToolsPythons = [
    "/Library/Developer/CommandLineTools/usr/bin/python3",
    "/Applications/Xcode.app/Contents/Developer/usr/bin/python3",
]
