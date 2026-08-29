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
    private let modelSetup = ModelSetup()
    private var setupWindow: SetupWindowController!
    private let permissions = PermissionsService()
    private var permissionsWindow: PermissionsWindowController!
    private var permissionsObservation: AnyCancellable?
    private var settingsObservation: AnyCancellable?
    private var cancelWordObservation: AnyCancellable?
    private var launchObservation: AnyCancellable?
    private var restartTask: Task<Void, Never>?
    private var settingsWindow: SettingsWindowController!
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

        setupWindow = SetupWindowController(setup: modelSetup, onRetry: { [weak self] in
            self?.bootstrap()
        })
        permissionsWindow = PermissionsWindowController(permissions: permissions)
        settingsWindow = SettingsWindowController()

        start()
    }

    /// Nothing works without the microphone and the right to paste into other
    /// apps, so ask for both before spending minutes on setup and models. Once
    /// they are in place the launch continues where it otherwise would have
    /// started.
    private func start() {
        permissions.refresh()

        guard !permissions.allGranted else {
            bootstrap()
            return
        }

        permissionsObservation = permissions.$states
            .first { PermissionsService.allGranted($0) }
            .sink { [weak self] _ in
                guard let self else { return }
                self.permissionsObservation = nil
                self.permissionsWindow.close()
                self.bootstrap()
            }

        permissionsWindow.show()
    }

    /// Bring up the engine, fetching the wake word models first if this Mac
    /// doesn't have them yet. That is what makes the distributed app runnable
    /// by unzipping and opening it, with no terminal step.
    private func bootstrap() {
        guard !modelSetup.isComplete else {
            startEngine()
            return
        }

        appState.status = .installing
        appState.errorMessage = nil
        setupWindow.show()

        Task { @MainActor in
            do {
                try await modelSetup.ensureModels()
                setupWindow.close()
                startEngine()
            } catch {
                // The window stays up showing the failure and a Try Again
                // button; the menu bar icon reflects it too.
                appState.status = .error
                appState.errorMessage = error.localizedDescription
            }
        }
    }

    private func startEngine() {
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

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let info = infoPlist()
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let name = info["CFBundleName"] as? String {
            options[.applicationName] = name
        }
        if let version = info["CFBundleShortVersionString"] as? String {
            options[.applicationVersion] = version
        }
        if let copyright = info["NSHumanReadableCopyright"] as? String {
            options[.init(rawValue: "Copyright")] = copyright
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    private func infoPlist() -> [String: Any] {
        if Bundle.main.infoDictionary?["NSHumanReadableCopyright"] != nil {
            return Bundle.main.infoDictionary ?? [:]
        }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return [:]
        }
        return plist
    }

    @objc private func showPermissions() {
        start()
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

        permissions.refresh()
        if permissions.allGranted {
            dictateMenuItem.title = appState.status.isActive ? "Stop Listening" : "Start Listening"
            menu.addItem(dictateMenuItem)
        } else {
            // Dictating is impossible until macOS says otherwise, so offer the
            // way out instead of a button that would do nothing.
            menu.addItem(NSMenuItem(title: "Grant Permissions…", action: #selector(showPermissions), keyEquivalent: ""))
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
