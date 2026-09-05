import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private let injector: TextInjecting = PasteboardTextInjector()
    private var statusItem: NSStatusItem!
    private var engine: EngineController!
    private var overlay: OverlayController!
    private let wakeWords = WakeWordSetup()
    private let permissions = PermissionsService()
    private var setup: SetupCoordinator!
    private var setupWindow: SetupWindowController!
    private var setupObservation: AnyCancellable?
    /// Mirrors setup's verdict into app state, where the menu bar mark reads
    /// it. Kept for the life of the app rather than dropped once setup
    /// finishes — a permission revoked later has to reach the icon too.
    private var setupMarkObservation: AnyCancellable?
    /// What stopped the wake word models arriving, if anything did. The menu
    /// carries it, since they have no window of their own to fail in.
    private var wakeWordFailure: String?
    private var settingsObservation: AnyCancellable?
    private var cancelWordObservation: AnyCancellable?
    private var modelObservation: AnyCancellable?
    private var launchObservation: AnyCancellable?
    private var restartTask: Task<Void, Never>?
    /// Whether the engine has been brought up. Not the same question as
    /// "is setup finished": the two are apart for as long as the wake word
    /// models take to arrive, which is the window `reloadModel()` has to stay
    /// out of.
    private var hasStartedEngine = false
    private var settingsWindow: SettingsWindowController!
    private let aboutWindow = AboutWindowController()
    private var dictateMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let iconView = NSHostingView(rootView: MenuBarIcon(appState: appState))
        iconView.frame = NSRect(x: 0, y: 0, width: 30, height: 22)
        statusItem.button?.subviews.forEach { $0.removeFromSuperview() }
        statusItem.button?.addSubview(iconView)
        statusItem.button?.frame = iconView.frame

        dictateMenuItem = NSMenuItem(title: "Start Listening", action: #selector(toggleDictation), keyEquivalent: "d")

        // Menu items are populated in menuNeedsUpdate(_:)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        engine = EngineController(appState: appState, injector: injector)
        overlay = OverlayController(appState: appState, onStop: { [weak self] in
            self?.engine.deactivate()
        }, onOpenSettings: { [weak self] in
            self?.openSettings()
        })

        settingsObservation = AppSettings.shared.$selectedLanguageCodes
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleRestart()
                }
            }

        cancelWordObservation = AppSettings.shared.$cancelWord
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleRestart()
                }
            }

        // Activating a model reloads at once rather than on the restart's one
        // second debounce: activating is a single deliberate click, not
        // something a user does three of in a row the way they tick languages.
        modelObservation = AppSettings.shared.$activeModelID
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.reloadModel()
                }
            }

        setup = SetupCoordinator(permissions: permissions)
        setupMarkObservation = setup.$isComplete
            .sink { [weak self] isComplete in
                self?.appState.needsSetup = !isComplete
            }
        setupWindow = SetupWindowController(setup: setup)
        settingsWindow = SettingsWindowController(appState: appState)

        start()
    }

    /// Nothing works without a model on disk, the microphone and the right to
    /// paste into other apps, so the setup window comes before the engine. Once
    /// it has all three the launch continues where it otherwise would have
    /// started.
    ///
    /// The same path serves a later launch that has lost one of them, and the
    /// menu bar's **Finish Setup…**.
    private func start() {
        setup.refresh()

        guard !setup.isComplete else {
            bootstrap()
            return
        }

        // Delivered on the next turn of the loop rather than straight from the
        // assignment that completed setup. The last thing to fall into place
        // is usually the model, whose activation writes `activeModelID` —
        // and `@Published` fires from `willSet`, so an engine built from here
        // synchronously would read the setting the activation replaced and
        // load a model that isn't on disk.
        setupObservation = setup.$isComplete
            .first { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.setupObservation = nil
                self.setupWindow.close()
                self.bootstrap()
            }

        setupWindow.show()
    }

    /// Bring up the engine, fetching the wake word models first if this Mac
    /// doesn't have them yet. That is what makes the distributed app runnable
    /// by unzipping and opening it, with no terminal step.
    ///
    /// They are not part of setup: nobody chooses them and there is nothing to
    /// decide, so they arrive in the background with the menu bar icon carrying
    /// the wait rather than in a window of their own.
    private func bootstrap() {
        guard !wakeWords.isComplete else {
            wakeWordFailure = nil
            startEngine()
            return
        }

        appState.status = .installing
        appState.errorMessage = nil
        wakeWordFailure = nil

        Task { @MainActor in
            do {
                try await wakeWords.ensureModels()
                startEngine()
            } catch {
                // Nothing is on screen to say so, so the icon and the menu are
                // where this shows.
                appState.status = .error
                appState.errorMessage = error.localizedDescription
                wakeWordFailure = error.localizedDescription
            }
        }
    }

    private func startEngine() {
        hasStartedEngine = true
        engine.start()

        if AppSettings.shared.dictateOnLaunch {
            launchObservation = appState.$status
                .first { $0 == .idle }
                .sink { [weak self] _ in
                    self?.engine.activate()
                    self?.launchObservation = nil
                }
        }
    }

    /// Overhear lives in the menu bar, so closing its last window — the
    /// permissions window on the way in, or setup, or settings — means the user
    /// is done with that window, not with the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    private func scheduleRestart() {
        restartTask?.cancel()
        restartTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            engine.stop()
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            engine.start()
        }
    }

    /// Swap the model the engine transcribes with.
    ///
    /// Stopping first is what discards the audio dictated so far: the listener
    /// goes with it, so a batch that was mid-transcription cannot arrive and be
    /// pasted after the swap. Dictation resumes afterwards if it was running,
    /// since the user activated a model rather than asking to stop.
    private func reloadModel() {
        // Setup activates the model it just downloaded, which is the same
        // setting written for a different reason: there is no engine to reload
        // yet, and `bootstrap()` starts one with the right model once it has
        // the wake word models too.
        //
        // Asked of the engine rather than of setup, which cannot answer it.
        // `isComplete` is set from the same `willSet` that woke this
        // observation, synchronously and before the hop below runs, so on the
        // launch where the model is the last requirement to settle it is
        // already true here. Starting the engine on the strength of that races
        // `bootstrap()`, which is still fetching the wake word models: the
        // engine comes up without them, fails to load the cancel word model,
        // and the start that `bootstrap()` makes afterwards finds an engine
        // already in place.
        guard hasStartedEngine else { return }

        let wasDictating = appState.status.isActive
        restartTask?.cancel()
        restartTask = Task { @MainActor in
            engine.stop()
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            engine.start()
            guard wasDictating else { return }
            launchObservation = appState.$status
                .first { $0 == .idle }
                .sink { [weak self] _ in
                    self?.engine.activate()
                    self?.launchObservation = nil
                }
        }
    }

    @objc private func showAbout() {
        aboutWindow.show()
    }

    @objc private func showSetup() {
        start()
    }

    @objc private func retryWakeWords() {
        bootstrap()
    }

    @objc private func toggleDictation() {
        if appState.status.isActive {
            engine.deactivate()
        } else if appState.status == .idle {
            engine.activate()
        }
    }

    @objc private func pasteTranscription(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        injector.inject(text: text)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        setup.refresh()
        if !setup.isComplete {
            // Dictating is impossible until setup has all three, so offer the
            // way out instead of a button that would do nothing.
            menu.addItem(NSMenuItem(title: "Finish Setup…", action: #selector(showSetup), keyEquivalent: ""))
        } else if let failure = wakeWordFailure {
            // The wake word models never reach the setup window, so this is the
            // only place their failure can be read.
            let reason = NSMenuItem(title: failure, action: nil, keyEquivalent: "")
            reason.isEnabled = false
            menu.addItem(reason)
            menu.addItem(NSMenuItem(title: "Try Again", action: #selector(retryWakeWords), keyEquivalent: ""))
        } else {
            dictateMenuItem.title = appState.status.isActive ? "Stop Listening" : "Start Listening"
            menu.addItem(dictateMenuItem)
        }

        menu.addItem(.separator())
        let heading = NSMenuItem(title: "Last Transcriptions", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        if appState.recentTranscriptions.isEmpty {
            let empty = NSMenuItem(title: "No transcriptions yet — they will appear here as you dictate", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for transcription in appState.recentTranscriptions {
                let truncated = transcription.count > 60
                    ? String(transcription.prefix(60)) + "…"
                    : transcription
                let item = NSMenuItem(title: truncated, action: #selector(pasteTranscription), keyEquivalent: "")
                item.representedObject = transcription
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About Overhear", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Overhear", action: #selector(quitApp), keyEquivalent: "q"))
    }
}
