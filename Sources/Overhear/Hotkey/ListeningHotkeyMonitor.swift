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

    /// The combination went down. What that means is the mode's business, not
    /// this one's: `AppDelegate` toggles on it in always-on listening and
    /// starts a session on it in hold to talk.
    var onPress: (() -> Void)?

    /// It came back up. Nothing to answer in always-on listening; the end of
    /// the session in hold to talk.
    var onRelease: (() -> Void)?

    /// It went down and will never come back up: the screen locked, the user
    /// was switched away, or the Mac went to sleep under a held key. Without
    /// this, hold to talk would leave a session running that nothing could end.
    var onLostPress: (() -> Void)?

    /// Set while the settings row is recording a combination. The tap is
    /// ahead of every app including this one, so without this the row would
    /// never see the keys being pressed at it — and the old combination would
    /// start dictation while the user was trying to replace it.
    var isSuspended = false

    private var hotkey: ListeningHotkey?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Whether the combination is down as far as the tap has seen. What tells a
    /// key's repeats from a fresh press, and what keeps a release from being
    /// reported for a press that was never made.
    private var isPressed = false

    /// Watches for the ways a session ends under a held key.
    private var sessionObservers: [(NotificationCenter, NSObjectProtocol)] = []

    /// Register a combination, or none. Safe to call repeatedly: settings
    /// changes arrive here, and so does the first launch, once setup has the
    /// grant the tap needs.
    func update(_ hotkey: ListeningHotkey?) {
        // Whatever was held was held on the old combination, and its release
        // will arrive as a key this no longer matches.
        isPressed = false
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
        watchForTheSessionGoingAway()
    }

    /// Notice the ways a held key stops being held without a release: the
    /// screen locking over it, the user switching away, the Mac sleeping.
    ///
    /// None of them sends a key up, so nothing else would ever report one.
    private func watchForTheSessionGoingAway() {
        guard sessionObservers.isEmpty else { return }

        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.sessionDidResignActiveNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification)
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"))
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.losePress() }
        }
        sessionObservers.append((center, token))
    }

    /// The key is down and its release will never be seen.
    private func losePress() {
        guard isPressed else { return }
        isPressed = false
        onLostPress?()
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
        isPressed = false
        for (center, token) in sessionObservers {
            center.removeObserver(token)
        }
        sessionObservers.removeAll()
    }

    /// What the tap does with one event: nil swallows it, anything else lets it
    /// through to the app underneath.
    ///
    /// Internal rather than private so the rules can be tested against
    /// synthesised events. Building the tap itself needs Accessibility and a
    /// real keystroke; deciding what an event means does not.
    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
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
            guard !hotkey.isModifierOnly, keyCode == hotkey.keyCode else { return pass }

            if type == .keyUp {
                // Matched on the key alone, without the modifiers the press
                // needed: a hand coming off ⌃⌥D rarely lets go of all three at
                // once, and a release read as somebody else's would leave a
                // hold running with nobody holding it. Swallowed for the same
                // reason the press was — the app underneath never saw the key
                // go down.
                guard isPressed else { return pass }
                isPressed = false
                onRelease?()
                return nil
            }

            // The repeats of a held key are swallowed with the press they come
            // from, so the app underneath never sees the tail of a combination
            // whose head it never saw. One press is one press, however long it
            // is held for.
            if isPressed { return nil }

            guard modifiers == hotkey.modifiers else { return pass }
            isPressed = true
            onPress?()
            return nil

        case .flagsChanged:
            guard hotkey.isModifierOnly, keyCode == hotkey.keyCode else { return pass }

            let isDown = modifiers == hotkey.modifiers
            if isDown, !isPressed {
                isPressed = true
                onPress?()
            } else if !isDown, isPressed {
                isPressed = false
                onRelease?()
            }
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
