import Foundation
@testable import Overhear

/// One instruction in a fake engine's script.
enum FakeEngineStep {
    /// Write a complete JSON line.
    case emit(String)
    /// Write exact bytes with no trailing newline — for split or batched writes.
    case raw(String)
    case wait(TimeInterval)
    case exit(Int32)

    static func event(_ name: String, _ fields: [String: String] = [:]) -> FakeEngineStep {
        var object: [String: Any] = ["event": name]
        for (key, value) in fields { object[key] = value }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let line = String(data: data, encoding: .utf8)
        else { return .emit("{\"event\":\"__encoding_failed__\"}") }
        return .emit(line)
    }
}

/// A stand-in for the Python engine: replays a scripted event sequence on stdout
/// and records every command it receives on stdin.
///
/// It stays alive until stdin closes or a `quit` command arrives, which is what
/// the real engine does, so `EngineProcess.stop()` behaves the same either way.
final class FakeEngine {
    let scriptURL: URL
    let commandLogURL: URL

    init(steps: [FakeEngineStep], directory: URL) throws {
        scriptURL = directory.appendingPathComponent("fake-engine.sh")
        commandLogURL = directory.appendingPathComponent("commands.log")

        FileManager.default.createFile(atPath: commandLogURL.path, contents: Data())

        // `sh` points an asynchronous command's stdin at /dev/null, so the
        // reader cannot use fd 0 directly — duplicate it to fd 3 first.
        var lines = [
            "#!/bin/sh",
            "CMDLOG='\(commandLogURL.path)'",
            // $PPID inside a subshell is inherited from the parent shell, so it
            // names the *test runner*, not this script. Capture the script's own
            // PID explicitly — otherwise `quit` terminates the test process.
            "MAIN=$$",
            "exec 3<&0",
            "(",
            "  while IFS= read -r line <&3; do",
            "    printf '%s\\n' \"$line\" >> \"$CMDLOG\"",
            "    case \"$line\" in",
            "      *'\"quit\"'*) kill -TERM \"$MAIN\" 2>/dev/null; exit 0;;",
            "    esac",
            "  done",
            ") &",
            "READER=$!",
        ]

        for step in steps {
            switch step {
            case .emit(let line):
                lines.append("printf '%s\\n' \(Self.quote(line))")
            case .raw(let text):
                lines.append("printf '%s' \(Self.quote(text))")
            case .wait(let seconds):
                lines.append("sleep \(seconds)")
            case .exit(let code):
                lines.append("kill $READER 2>/dev/null; exit \(code)")
            }
        }

        // Outlive the script's output: block until stdin closes so the process
        // behaves like a real engine waiting for commands.
        lines.append("wait $READER")

        let script = lines.joined(separator: "\n") + "\n"
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: scriptURL.path)
    }

    var launch: EngineLaunch {
        EngineLaunch(executablePath: "/bin/sh", arguments: [scriptURL.path])
    }

    /// Commands the host has sent, in order, as raw JSON lines.
    var commandsReceived: [String] {
        guard let contents = try? String(contentsOf: commandLogURL, encoding: .utf8) else { return [] }
        return contents.split(separator: "\n").map(String.init)
    }

    /// Just the `command` values, e.g. ["activate", "deactivate"].
    var commandNames: [String] {
        commandsReceived.compactMap { line in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return json["command"] as? String
        }
    }

    private static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
