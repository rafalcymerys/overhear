import AppKit

/// What a press means while the settings row is listening for one.
///
/// Kept apart from the view and from the event monitor that feeds it, because
/// this is the part with rules: which presses are a shortcut, which are a way
/// out, and which are neither and leave the row waiting.
struct HotkeyRecorder {
    enum Outcome: Equatable {
        /// A combination to store.
        case recorded(ListeningHotkey)
        /// Not a combination we can use, and why. The row keeps recording —
        /// the user has not been given what they asked for yet.
        case refused(String)
        /// Escape. The row stops, and whatever was set before still is.
        case cancelled
        /// Part of a combination still being pressed, chiefly a modifier on
        /// its way down.
        case pending
    }

    private let system: SystemShortcuts

    /// The modifier held on its own, if one is down: its key, so Right Option
    /// is not mistaken for Left, and its flag.
    private var held: (keyCode: UInt16, modifiers: NSEvent.ModifierFlags)?

    init(system: SystemShortcuts = .current) {
        self.system = system
    }

    private static let escape: UInt16 = 53

    mutating func keyDown(keyCode: UInt16,
                          characters: String,
                          modifiers: NSEvent.ModifierFlags) -> Outcome {
        let modifiers = ListeningHotkey.normalized(modifiers)
        held = nil

        if keyCode == Self.escape && modifiers.isEmpty {
            return .cancelled
        }

        guard !modifiers.isEmpty else {
            // A letter on its own would be swallowed everywhere the user
            // types, which is a worse app than the one with no hotkey at all.
            return .refused("Hold ⌃, ⌥, ⇧ or ⌘ as part of the combination.")
        }

        let hotkey = ListeningHotkey(keyCode: keyCode,
                                     character: characters.lowercased(),
                                     modifiers: modifiers)
        guard !hotkey.isModifierOnly else { return .pending }
        guard !system.isTaken(hotkey) else {
            return .refused("\(hotkey.displayString) is already used by macOS.")
        }
        return .recorded(hotkey)
    }

    /// A modifier is a hotkey only once it is let go of. Until then it could
    /// as easily be the first half of ⌃⌥D, so holding one waits to see.
    mutating func flagsChanged(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Outcome {
        let modifiers = ListeningHotkey.normalized(modifiers)

        if modifiers.isEmpty {
            guard let held, held.keyCode == keyCode else {
                self.held = nil
                return .pending
            }
            self.held = nil
            return .recorded(ListeningHotkey(keyCode: keyCode,
                                             character: "",
                                             modifiers: held.modifiers))
        }

        // Exactly one, or this is a chord on its way to a key.
        held = modifiers.rawValue.nonzeroBitCount == 1 ? (keyCode, modifiers) : nil
        return .pending
    }
}
