import AppKit
import SwiftUI

/// The recorder as the settings pane sees it: a row that waits for a
/// combination, stores it, and says when it cannot.
///
/// The rules are `HotkeyRecorder`'s; what is here is the plumbing they need —
/// a local event monitor while the row is listening, and the global tap held
/// off for as long as that lasts.
@MainActor
final class HotkeyRecording: ObservableObject {
    @Published private(set) var isRecording = false

    /// Why the last combination was not taken, shown under the row. Cleared
    /// when recording starts again rather than when it ends, so the reason
    /// stays readable after the row stops waiting.
    @Published private(set) var refusal: String?

    private let settings: AppSettings
    private let monitor: ListeningHotkeyMonitor
    private var recorder = HotkeyRecorder()
    private var localMonitor: Any?

    /// - Parameters are the shared ones, taken here rather than as defaults on
    ///   the signature: both are main-actor isolated, which a default argument
    ///   is not. Tests pass their own.
    init(settings: AppSettings? = nil, monitor: ListeningHotkeyMonitor? = nil) {
        self.settings = settings ?? .shared
        self.monitor = monitor ?? .shared
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    func begin() {
        guard !isRecording else { return }

        recorder = HotkeyRecorder()
        refusal = nil
        isRecording = true
        // Recording never triggers what it is bound to. The tap is ahead of
        // this window, so without holding it off the combination already
        // stored would start dictation instead of being replaced.
        monitor.isSuspended = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.receive(event) } ? nil : event
        }
    }

    /// Stop waiting and leave whatever was set before in place.
    func cancel() {
        guard isRecording else { return }
        end()
    }

    func clear() {
        refusal = nil
        settings.listeningHotkey = nil
    }

    /// - Returns: whether the event was the row's rather than the window's. A
    ///   combination pressed at a recorder should not also reach the button
    ///   under it, or beep for being a shortcut nothing answers to.
    private func receive(_ event: NSEvent) -> Bool {
        let outcome: HotkeyRecorder.Outcome
        switch event.type {
        case .keyDown:
            outcome = recorder.keyDown(keyCode: event.keyCode,
                                       characters: event.charactersIgnoringModifiers ?? "",
                                       modifiers: event.modifierFlags)
        case .flagsChanged:
            outcome = recorder.flagsChanged(keyCode: event.keyCode, modifiers: event.modifierFlags)
        default:
            return false
        }

        switch outcome {
        case let .recorded(hotkey):
            settings.listeningHotkey = hotkey
            end()
        case let .refused(reason):
            refusal = reason
        case .cancelled:
            end()
        case .pending:
            break
        }
        return true
    }

    private func end() {
        isRecording = false
        monitor.isSuspended = false
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
    }
}

/// The **Listening hotkey** row in the General pane.
struct HotkeyRecorderRow: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var recording = HotkeyRecording()

    var body: some View {
        // The explanation shares the row rather than sitting in the section's
        // footer, which grouped forms render outside the card.
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Listening hotkey")
                Spacer()
                Button(buttonTitle) {
                    if recording.isRecording {
                        recording.cancel()
                    } else {
                        recording.begin()
                    }
                }
                if settings.listeningHotkey != nil && !recording.isRecording {
                    Button {
                        recording.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear the hotkey")
                }
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(recording.refusal == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Clicking away is not a way of recording something: the row stops
        // waiting and what was set before stays set.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            recording.cancel()
        }
    }

    private var buttonTitle: String {
        if recording.isRecording { return "Press a combination…" }
        return settings.listeningHotkey?.displayString ?? "Record Shortcut"
    }

    private var caption: String {
        if let refusal = recording.refusal { return refusal }
        return "Use a global keyboard shortcut to toggle the listening on and off."
    }
}
