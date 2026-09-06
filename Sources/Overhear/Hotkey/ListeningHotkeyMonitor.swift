import AppKit

/// Watches for the listening hotkey wherever the user is typing.
///
/// A session event tap rather than `RegisterEventHotKey`, which cannot
/// register a modifier held on its own, or `addGlobalMonitorForEvents`, which
/// only watches and so leaves the keystroke to land in whatever the user was
/// typing into. The tap sees both and can swallow what it acts on.
///
/// It needs Accessibility, which Overhear already has: pasting is a synthetic
/// Cmd+V, gated behind the same grant. Setup is what asks for it, so a tap
/// that cannot be created here is a launch where nothing works yet — hence
/// `update(_:)` builds one whenever it is called without one, rather than
/// giving up at launch.
@MainActor
final class ListeningHotkeyMonitor {
    static let shared = ListeningHotkeyMonitor()

    /// What a press runs. `AppDelegate` points this at the same toggle the
    /// menu item uses, which acts only when the engine is idle or dictating —
    /// so a press during the load or after a failure does nothing, exactly as
    /// the menu does.
    var onToggle: (() -> Void)?

    /// Set while the settings row is recording a combination. The tap is
    /// ahead of every app including this one, so without this the row would
    /// never see the keys being pressed at it — and the old combination would
    /// start dictation while the user was trying to replace it.
    var isSuspended = false

    private var hotkey: ListeningHotkey?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Register a combination, or none. Safe to call repeatedly: settings
    /// changes arrive here, and so does the first launch, once setup has the
    /// grant the tap needs.
    func update(_ hotkey: ListeningHotkey?) {
        self.hotkey = hotkey
        if hotkey == nil {
            stop()
        } else {
            start()
        }
    }

    private func start() {
        guard tap == nil else { return }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: listeningHotkeyTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            // No Accessibility yet. Setup asks for it, and the next call here
            // — the grant reaching the engine, or a combination recorded —
            // tries again.
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        runLoopSource = source
    }

    private func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        // macOS switches a tap off if it ever takes too long over an event, or
        // when the user's own input says something has gone wrong. Neither is
        // a reason to stop watching, and nothing else will turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }

        guard !isSuspended, let hotkey else { return pass }

        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = ListeningHotkey.normalized(NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))

        switch type {
        case .keyDown, .keyUp:
            guard !hotkey.isModifierOnly,
                  keyCode == hotkey.keyCode,
                  modifiers == hotkey.modifiers else { return pass }

            // Held down is one toggle. The repeats are swallowed with the
            // press they come from, so the app underneath never sees the tail
            // of a combination whose head it never saw.
            if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                onToggle?()
            }
            return nil

        case .flagsChanged:
            guard hotkey.isModifierOnly, keyCode == hotkey.keyCode else { return pass }
            // Down, rather than up: the release is what hold-to-listen will
            // read, and acting on both would toggle twice per press.
            if modifiers == hotkey.modifiers { onToggle?() }
            // Passed on regardless. A modifier types nothing, and every app
            // tracks which ones are down — swallowing it would leave them
            // believing this one still is.
            return pass

        default:
            return pass
        }
    }
}

/// Runs on the main run loop, which is where the tap's source was added.
private let listeningHotkeyTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<ListeningHotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    return MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
}
