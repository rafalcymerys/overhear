import Foundation

@MainActor
final class EngineProcess {
    private let appState: AppState
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stdinPipe: Pipe?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        guard process == nil else { return }

        appState.status = .loading

        let enginePath = Self.findEnginePath()
        guard let enginePath else {
            appState.status = .error
            appState.errorMessage = "Could not find dictation_engine.py"
            return
        }

        let pythonPath = Self.findPython()
        guard let pythonPath else {
            appState.status = .error
            appState.errorMessage = "Python 3 not found. Run: brew install python3"
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        let languages = Array(AppSettings.shared.selectedLanguageCodes).joined(separator: ",")
        let cancelWord = AppSettings.shared.cancelWord.modelValue
        proc.arguments = ["-u", enginePath, "--languages", languages, "--cancel-word", cancelWord]
        proc.environment = ProcessInfo.processInfo.environment

        let stdout = Pipe()
        let stdin = Pipe()
        proc.standardOutput = stdout
        proc.standardInput = stdin
        proc.standardError = FileHandle.nullDevice

        self.stdoutPipe = stdout
        self.stdinPipe = stdin
        self.process = proc

        proc.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }
                if self.appState.status != .stopped {
                    self.appState.status = .error
                    self.appState.errorMessage = "Engine exited with code \(proc.terminationStatus)"
                }
                self.process = nil
            }
        }

        Task.detached { [weak self] in
            self?.readOutput(pipe: stdout)
        }

        do {
            try proc.run()
        } catch {
            appState.status = .error
            appState.errorMessage = "Failed to start engine: \(error.localizedDescription)"
            process = nil
        }
    }

    func activate() {
        sendCommand(["command": "activate"])
    }

    func deactivate() {
        sendCommand(["command": "deactivate"])
    }

    func stop() {
        sendCommand(["command": "quit"])
        let proc = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            proc?.terminate()
        }
        Task { @MainActor in
            appState.status = .stopped
            appState.errorMessage = nil
        }
    }

    private func sendCommand(_ cmd: [String: String]) {
        guard let stdinPipe, let data = try? JSONSerialization.data(withJSONObject: cmd) else { return }
        var payload = data
        payload.append(contentsOf: [UInt8(ascii: "\n")])
        try? stdinPipe.fileHandleForWriting.write(contentsOf: payload)
    }

    private nonisolated func readOutput(pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        var buffer = Data()

        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            buffer.append(data)

            while let newlineRange = buffer.range(of: Data([UInt8(ascii: "\n")])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                guard String(data: lineData, encoding: .utf8) != nil,
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let event = json["event"] as? String
                else { continue }

                Task { @MainActor in
                    self.handleEvent(event, json: json)
                }
            }
        }
    }

    @MainActor
    private func handleEvent(_ event: String, json: [String: Any]) {
        switch event {
        case "status":
            if let message = json["message"] as? String {
                switch message {
                case "loading_models": appState.status = .loading
                case "wake_word_ready", "whisper_ready": break
                default: break
                }
            }

        case "idle":
            appState.status = .idle

        case "ready":
            appState.status = .ready

        case "speech_start":
            appState.status = .listening

        case "transcribing":
            appState.status = .transcribing

        case "transcription":
            if let text = json["text"] as? String, !text.isEmpty {
                appState.addTranscription(text)
                TextInjector.inject(text: text)
            }

        case "transcription_empty":
            break

        case "wake_word_cancel":
            appState.status = .ready
            appState.triggerCancelled()

        case "error":
            appState.status = .error
            appState.errorMessage = json["message"] as? String

        case "warning":
            break

        default:
            break
        }
    }

    private static func findEnginePath() -> String? {
        let candidates = [
            Bundle.main.path(forResource: "dictation_engine", ofType: "py", inDirectory: "Engine"),
            Bundle.main.resourcePath.map { "\($0)/Engine/dictation_engine.py" },
            {
                let dir = URL(fileURLWithPath: #file).deletingLastPathComponent().path
                return "\(dir)/../../Engine/dictation_engine.py"
            }(),
            "./Engine/dictation_engine.py",
            FileManager.default.currentDirectoryPath + "/Engine/dictation_engine.py",
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }

        if let execURL = Bundle.main.executableURL {
            let projectRoot = execURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let path = projectRoot.appendingPathComponent("Engine/dictation_engine.py").path
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    private static func findPython() -> String? {
        // Prefer venv python so dependencies are available
        var venvCandidates: [String] = []

        // Check next to the engine script
        if let enginePath = findEnginePath() {
            let engineDir = URL(fileURLWithPath: enginePath).deletingLastPathComponent()
            let projectRoot = engineDir.deletingLastPathComponent()
            venvCandidates.append(projectRoot.appendingPathComponent(".venv/bin/python3").path)
        }

        // Check inside app bundle Resources
        if let resourcePath = Bundle.main.resourcePath {
            venvCandidates.append(resourcePath + "/.venv/bin/python3")
        }

        // Check next to the .app bundle itself
        if let bundlePath = Bundle.main.bundlePath as String? {
            let appDir = URL(fileURLWithPath: bundlePath).deletingLastPathComponent()
            venvCandidates.append(appDir.appendingPathComponent(".venv/bin/python3").path)
        }

        // Check ~/Library/Application Support/Overhear
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Overhear/.venv/bin/python3")
        venvCandidates.append(appSupport.path)

        for path in venvCandidates where FileManager.default.fileExists(atPath: path) {
            return path
        }

        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        let whichResult = try? shellOutput("which python3")
        return whichResult?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shellOutput(_ command: String) throws -> String {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", command]
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
