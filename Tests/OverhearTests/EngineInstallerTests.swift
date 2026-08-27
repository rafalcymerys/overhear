import XCTest
@testable import Overhear

@MainActor
final class EngineInstallerTests: OverhearTestCase {
    private let digest = "abc123"

    // B22 — deciding whether setup has to run

    func testFirstLaunchInstalls() {
        let decision = EngineInstaller.decide(
            existingVenvPython: nil,
            managedVenvPython: "/managed/.venv/bin/python3",
            managedStamp: nil,
            requirementsDigest: digest
        )

        XCTAssertEqual(decision, .install(.firstLaunch))
    }

    func testASourceCheckoutVenvIsLeftAlone() {
        let decision = EngineInstaller.decide(
            existingVenvPython: "/Users/dev/overhear/.venv/bin/python3",
            managedVenvPython: "/managed/.venv/bin/python3",
            managedStamp: nil,
            requirementsDigest: digest
        )

        XCTAssertEqual(decision, .ready, "the developer owns that environment")
    }

    func testMatchingStampSkipsSetup() {
        let decision = EngineInstaller.decide(
            existingVenvPython: "/managed/.venv/bin/python3",
            managedVenvPython: "/managed/.venv/bin/python3",
            managedStamp: digest,
            requirementsDigest: digest
        )

        XCTAssertEqual(decision, .ready)
    }

    func testChangedRequirementsReinstall() {
        let decision = EngineInstaller.decide(
            existingVenvPython: "/managed/.venv/bin/python3",
            managedVenvPython: "/managed/.venv/bin/python3",
            managedStamp: "an older digest",
            requirementsDigest: digest
        )

        XCTAssertEqual(decision, .install(.dependenciesChanged))
    }

    func testAnInterruptedInstallIsRetried() {
        let decision = EngineInstaller.decide(
            existingVenvPython: "/managed/.venv/bin/python3",
            managedVenvPython: "/managed/.venv/bin/python3",
            managedStamp: nil,
            requirementsDigest: digest
        )

        XCTAssertEqual(decision, .install(.interrupted))
    }

    // B23 — the stamp, written by the script and read by the app

    func testDigestMatchesShasum() throws {
        let file = tempDirectory.appendingPathComponent("requirements.txt")
        try "openwakeword>=0.6.0\nfaster-whisper>=1.0.0\n".write(to: file, atomically: true, encoding: .utf8)

        let fromShasum = try shell("shasum -a 256 '\(file.path)' | awk '{print $1}'")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(try EngineInstaller.digest(ofFileAt: file), fromShasum,
                       "install.sh writes the stamp with shasum; the app has to read the same value")
    }

    func testStampIsReadFromTheVenvAndTrimmed() throws {
        let venv = tempDirectory.appendingPathComponent(".venv")
        try FileManager.default.createDirectory(at: venv, withIntermediateDirectories: true)

        XCTAssertNil(EngineInstaller.readStamp(inVenv: venv))

        try "  \(digest)\n".write(to: EngineInstaller.stampFile(inVenv: venv), atomically: true, encoding: .utf8)
        XCTAssertEqual(EngineInstaller.readStamp(inVenv: venv), digest)
    }

    func testBlankStampCountsAsMissing() throws {
        let venv = tempDirectory.appendingPathComponent(".venv")
        try FileManager.default.createDirectory(at: venv, withIntermediateDirectories: true)
        try "\n".write(to: EngineInstaller.stampFile(inVenv: venv), atomically: true, encoding: .utf8)

        XCTAssertNil(EngineInstaller.readStamp(inVenv: venv))
    }

    // B24 — progress reporting

    func testOnlyMarkedLinesBecomeProgress() {
        XCTAssertEqual(EngineInstaller.progressMessage(in: ">>> Installing Python dependencies…"),
                       "Installing Python dependencies…")
        XCTAssertNil(EngineInstaller.progressMessage(in: "Collecting numpy>=1.24.0"))
        XCTAssertNil(EngineInstaller.progressMessage(in: ">>>   "))
    }

    // B25 — running the script

    func testProgressLinesReachTheUIAndOutputIsLogged() async throws {
        let installer = EngineInstaller()
        let environment = try fakeScript(body: """
        echo ">>> Creating the Python environment…"
        echo "detail that belongs in the log"
        echo ">>> Downloading the Whisper model…"
        """)

        try await installer.install(using: environment)

        XCTAssertEqual(installer.step, "Setup complete.")
        XCTAssertNil(installer.failure)
        XCTAssertFalse(installer.isInstalling)

        let log = try String(contentsOf: environment.logFile, encoding: .utf8)
        XCTAssertTrue(log.contains("detail that belongs in the log"))
        XCTAssertTrue(log.contains(">>> Downloading the Whisper model…"))
    }

    func testTheReasonIsPublishedForTheSetupWindow() async throws {
        let installer = EngineInstaller()
        installer.prepare(reason: .dependenciesChanged)

        XCTAssertEqual(installer.reason, .dependenciesChanged)
        XCTAssertNil(installer.failure)

        try await installer.install(using: try fakeScript(body: "true"), reason: .interrupted)
        XCTAssertEqual(installer.reason, .interrupted)
    }

    func testTheScriptReceivesTheResolvedPaths() async throws {
        let installer = EngineInstaller()
        let environment = try fakeScript(body: #"echo "args: $*""#)

        try await installer.install(using: environment)

        let log = try String(contentsOf: environment.logFile, encoding: .utf8)
        XCTAssertTrue(log.contains("--venv \(environment.venvDirectory.path)"), log)
        XCTAssertTrue(log.contains("--requirements \(environment.requirements.path)"), log)
        XCTAssertTrue(log.contains("--python \(environment.python)"), log)
    }

    func testAFailingScriptReportsItsLastOutput() async throws {
        let installer = EngineInstaller()
        let environment = try fakeScript(body: """
        echo "Collecting faster-whisper"
        echo "ERROR: no matching distribution found" >&2
        exit 3
        """)

        do {
            try await installer.install(using: environment)
            XCTFail("expected the failed install to throw")
        } catch let error as EngineInstaller.InstallError {
            guard case let .failed(status, output) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(status, 3)
            XCTAssertTrue(output.contains("ERROR: no matching distribution found"), output)
        }

        XCTAssertFalse(installer.isInstalling)
        let failure = try XCTUnwrap(installer.failure)
        XCTAssertTrue(failure.contains("exit code 3"), failure)
    }

    func testAMissingScriptIsReportedRatherThanCrashing() async {
        let installer = EngineInstaller()
        let environment = EngineInstaller.Environment(
            script: tempDirectory.appendingPathComponent("nope.sh"),
            requirements: tempDirectory.appendingPathComponent("requirements.txt"),
            python: "/usr/bin/python3",
            venvDirectory: tempDirectory.appendingPathComponent(".venv"),
            logFile: tempDirectory.appendingPathComponent("install.log")
        )

        do {
            try await installer.install(using: environment)
            XCTFail("expected a missing script to throw")
        } catch {
            XCTAssertNotNil(installer.failure)
            XCTAssertFalse(installer.isInstalling)
        }
    }

    // B26 — waiting out the system's Command Line Tools install

    func testAMacThatAlreadyHasPythonDoesNotWait() async throws {
        let installer = EngineInstaller()
        installer.prepare(reason: .firstLaunch)
        let probe = PythonProbe(found: "/opt/homebrew/bin/python3")

        let python = try await installer.awaitInstallerPython(pollInterval: .seconds(60), probe: { probe($0) })

        XCTAssertEqual(python, "/opt/homebrew/bin/python3")
        XCTAssertEqual(probe.requestsMade, [true])
        XCTAssertEqual(installer.step, "Preparing…")
    }

    func testSetupResumesOnceTheDeveloperToolsInstallFinishes() async throws {
        let installer = EngineInstaller()
        installer.prepare(reason: .firstLaunch)
        let probe = PythonProbe()

        let waiting = Task {
            try await installer.awaitInstallerPython(pollInterval: .milliseconds(10), probe: { probe($0) })
        }
        await waitUntil("the setup window to say what it is waiting for") {
            installer.step == EngineInstaller.waitingForDeveloperToolsStep
        }

        // What the user does in the system's installer window.
        probe.finishInstalling(python: "/usr/bin/python3")

        let python = try await waiting.value
        XCTAssertEqual(python, "/usr/bin/python3", "setup continues without a relaunch")
        XCTAssertEqual(installer.step, "Preparing…")
        XCTAssertEqual(probe.requestsMade.first, true)
        XCTAssertFalse(probe.requestsMade.dropFirst().contains(true),
                       "only the first probe may ask macOS to install the tools")
    }

    func testTheStubIsOnlyRunWhenItCanHelp() {
        XCTAssertTrue(EngineInstaller.mayProbe("/usr/bin/python3", mayRequestDeveloperTools: true, developerToolsInstalled: false),
                      "running the stub is how the install gets requested in the first place")
        XCTAssertFalse(EngineInstaller.mayProbe("/usr/bin/python3", mayRequestDeveloperTools: false, developerToolsInstalled: false),
                       "polling must not talk over the dialog the user is answering")
        XCTAssertTrue(EngineInstaller.mayProbe("/usr/bin/python3", mayRequestDeveloperTools: false, developerToolsInstalled: true))
        XCTAssertTrue(EngineInstaller.mayProbe("/opt/homebrew/bin/python3", mayRequestDeveloperTools: false, developerToolsInstalled: false))
    }

    func testAFailureToFindThePiecesReachesTheSetupWindow() async {
        let installer = EngineInstaller()

        do {
            try await installer.install(reason: .firstLaunch) {
                throw EngineInstaller.InstallError.scriptNotFound
            }
            XCTFail("expected the missing script to throw")
        } catch {
            XCTAssertEqual(installer.failure, EngineInstaller.InstallError.scriptNotFound.errorDescription,
                           "otherwise the window spins on \"Preparing…\" until the user quits")
            XCTAssertFalse(installer.isInstalling)
        }
    }

    // MARK: - Helpers

    /// A stand-in for install.sh: same interface, none of the downloading.
    private func fakeScript(body: String) throws -> EngineInstaller.Environment {
        let script = tempDirectory.appendingPathComponent("install.sh")
        try "#!/bin/bash\nset -euo pipefail\n\(body)\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let requirements = tempDirectory.appendingPathComponent("requirements.txt")
        try "numpy>=1.24.0\n".write(to: requirements, atomically: true, encoding: .utf8)

        return EngineInstaller.Environment(
            script: script,
            requirements: requirements,
            python: "/usr/bin/python3",
            venvDirectory: tempDirectory.appendingPathComponent(".venv"),
            logFile: tempDirectory.appendingPathComponent("install.log")
        )
    }

    private func shell(_ command: String) throws -> String {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-c", command]
        proc.standardOutput = pipe
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// A stand-in for looking the system over for a Python: answers nil until the
/// developer tools "finish installing", and remembers whether each probe was
/// allowed to ask macOS to start that install.
private final class PythonProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var found: String?
    private var requests: [Bool] = []

    init(found: String? = nil) {
        self.found = found
    }

    func callAsFunction(_ mayRequestDeveloperTools: Bool) -> String? {
        lock.lock()
        defer { lock.unlock() }
        requests.append(mayRequestDeveloperTools)
        return found
    }

    func finishInstalling(python: String) {
        lock.lock()
        defer { lock.unlock() }
        found = python
    }

    var requestsMade: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}
