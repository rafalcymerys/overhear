import Foundation

/// How to launch the engine: which executable, with which arguments.
struct EngineLaunch {
    var executablePath: String
    var arguments: [String]
}

enum EngineLaunchError: LocalizedError {
    case engineNotFound
    case pythonNotFound

    var errorDescription: String? {
        switch self {
        case .engineNotFound: return "Could not find dictation_engine.py"
        case .pythonNotFound: return "Python 3 not found. Run: brew install python3"
        }
    }
}

@MainActor
final class EngineProcess {
    /// Resolves what to launch. Injected so tests can substitute a fake engine
    /// without touching the filesystem probing below.
    typealias LaunchResolver = @MainActor () throws -> EngineLaunch

    private let appState: AppState
    private let injector: TextInjecting
    private let resolveLaunch: LaunchResolver
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stdinPipe: Pipe?

    init(appState: AppState,
         injector: TextInjecting = PasteboardTextInjector(),
         resolveLaunch: @escaping LaunchResolver = EngineProcess.defaultLaunch) {
        _ = Self.ignoreBrokenPipes
        self.appState = appState
        self.injector = injector
        self.resolveLaunch = resolveLaunch
    }

    /// The production resolver: locate the bundled engine script and a Python
    /// interpreter, and build the argument list from current settings.
    @MainActor
    static func defaultLaunch() throws -> EngineLaunch {
        guard let enginePath = findEnginePath() else { throw EngineLaunchError.engineNotFound }
        guard let pythonPath = findPython() else { throw EngineLaunchError.pythonNotFound }

        let languages = Array(AppSettings.shared.selectedLanguageCodes).joined(separator: ",")
        let cancelWord = AppSettings.shared.cancelWord.modelValue
        return EngineLaunch(
            executablePath: pythonPath,
            arguments: ["-u", enginePath, "--languages", languages, "--cancel-word", cancelWord]
        )
    }

    func start() {
        guard process == nil else { return }

        appState.status = .loading

        let launch: EngineLaunch
        do {
            launch = try resolveLaunch()
        } catch {
            appState.status = .error
            appState.errorMessage = error.localizedDescription
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launch.executablePath)
        proc.arguments = launch.arguments
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
        // Mark the shutdown as intentional *before* asking the engine to quit.
        // terminationHandler treats any exit while the status is not .stopped as
        // a crash, and deferring this to a Task left a window where a prompt
        // exit would be misreported as an error.
        appState.status = .stopped
        appState.errorMessage = nil

        sendCommand(["command": "quit"])
        let proc = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            proc?.terminate()
        }
    }

    /// Writing to a pipe whose reader has gone raises SIGPIPE, which by default
    /// terminates the whole app. That is reachable in normal use: if the engine
    /// dies, the next `activate`/`deactivate`/`quit` would take the app down
    /// with it. Ignore the signal so the write reports EPIPE instead.
    private static let ignoreBrokenPipes: Void = {
        signal(SIGPIPE, SIG_IGN)
    }()

    private func sendCommand(_ cmd: [String: String]) {
        guard let process, process.isRunning,
              let stdinPipe,
              let data = try? JSONSerialization.data(withJSONObject: cmd)
        else { return }
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
                injector.inject(text: text)
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

    /// Internal rather than private: the installer resolves interpreters the
    /// same way, and that starts from where the engine script sits.
    static func findEnginePath() -> String? {
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

    nonisolated static let systemPythonCandidates = [
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/usr/bin/python3",
    ]

    /// Interpreters to try, most preferred first.
    ///
    /// Venv interpreters come before any system Python: the engine's
    /// dependencies only exist inside the venv, so a system interpreter that
    /// happens to be found first would start and then immediately fail on
    /// `import sounddevice`.
    static func pythonCandidates(enginePath: String?,
                                 resourcePath: String?,
                                 bundlePath: String?,
                                 home: URL) -> [String] {
        var candidates: [String] = []

        // Next to the engine script
        if let enginePath {
            let projectRoot = URL(fileURLWithPath: enginePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            candidates.append(projectRoot.appendingPathComponent(".venv/bin/python3").path)
        }

        // Inside the app bundle's Resources
        if let resourcePath {
            candidates.append(resourcePath + "/.venv/bin/python3")
        }

        // Next to the .app bundle itself
        if let bundlePath {
            let appDir = URL(fileURLWithPath: bundlePath).deletingLastPathComponent()
            candidates.append(appDir.appendingPathComponent(".venv/bin/python3").path)
        }

        // ~/Library/Application Support/Overhear
        candidates.append(
            home.appendingPathComponent("Library/Application Support/Overhear/.venv/bin/python3").path
        )

        return candidates + systemPythonCandidates
    }

    private static func findPython() -> String? {
        let candidates = pythonCandidates(
            enginePath: findEnginePath(),
            resourcePath: Bundle.main.resourcePath,
            bundlePath: Bundle.main.bundlePath,
            home: FileManager.default.homeDirectoryForCurrentUser
        )
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        let whichResult = try? shellOutput("which python3")
        let trimmed = whichResult?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
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
