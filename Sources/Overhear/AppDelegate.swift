import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private let injector: TextInjecting = PasteboardTextInjector()
    private var statusItem: NSStatusItem!
    private var engine: EngineProcess!
    private var overlay: OverlayController!
    private var settingsObservation: AnyCancellable?
    private var cancelWordObservation: AnyCancellable?
    private var launchObservation: AnyCancellable?
    private var restartTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?
    private var dictateMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let iconView = NSHostingView(rootView: MenuBarIcon(appState: appState))
        iconView.frame = NSRect(x: 0, y: 0, width: 30, height: 22)
        statusItem.button?.subviews.forEach { $0.removeFromSuperview() }
        statusItem.button?.addSubview(iconView)
        statusItem.button?.frame = iconView.frame

        dictateMenuItem = NSMenuItem(title: "Start Dictating", action: #selector(toggleDictation), keyEquivalent: "d")

        // Menu items are populated in menuNeedsUpdate(_:)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        engine = EngineProcess(appState: appState, injector: injector)
        overlay = OverlayController(appState: appState, onStop: { [weak self] in
            self?.engine.deactivate()
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

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Overhear Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
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

        dictateMenuItem.title = appState.status.isActive ? "Stop Dictating" : "Start Dictating"
        menu.addItem(dictateMenuItem)

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
