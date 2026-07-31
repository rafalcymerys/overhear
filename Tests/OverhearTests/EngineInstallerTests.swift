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
