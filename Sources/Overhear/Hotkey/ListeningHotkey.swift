import AppKit

/// The combination that starts and stops listening from wherever the user is
/// typing.
///
/// Two shapes, because two things have to be said about the same press. A key
/// with modifiers — ⌃⌥D — is what the menu can draw and what the tap swallows
/// before the app underneath sees it. A modifier held on its own is neither:
/// it types nothing, so nothing has to be swallowed, and `NSMenuItem` has no
/// way to draw it. The second shape exists because a key that types nothing
/// while it is down is what hold-to-listen will want.
struct ListeningHotkey: Equatable {
    /// The virtual key code the event tap matches on. For a modifier held on
    /// its own it is that modifier's own key — which is how Right Option is
    /// told from Left, a distinction `NSEvent.ModifierFlags` does not carry.
    let keyCode: UInt16

    /// What the key types with nothing held, lowercased: `d` for ⌃⌥D. Empty
    /// for a modifier on its own.
    ///
    /// Recorded rather than derived, because deriving it means asking the
    /// current keyboard layout what a key code means — and this is also the
    /// string `NSMenuItem.keyEquivalent` wants.
    let character: String

    let modifiers: NSEvent.ModifierFlags

    /// A modifier held on its own, with no key to go with it.
    var isModifierOnly: Bool { character.isEmpty }

    /// What the settings row shows, in the order macOS writes shortcuts in.
    var displayString: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols + Self.keyLabel(keyCode: keyCode, character: character)
    }

    /// What `NSMenuItem` draws beside the item, and answers to while the menu
    /// is open. Empty for a modifier on its own, which a menu cannot show.
    var menuKeyEquivalent: String { character }

    /// Keys whose character is blank or unreadable in a menu. Anything else
    /// draws as itself, uppercased.
    private static let namedKeys: [UInt16: String] = [
        49: "␣",   // space
        36: "↩",   // return
        48: "⇥",   // tab
        51: "⌫",   // delete
    ]

    private static func keyLabel(keyCode: UInt16, character: String) -> String {
        guard !character.isEmpty else { return "" }
        return namedKeys[keyCode] ?? character.uppercased()
    }

    /// The modifiers worth storing: the four a shortcut is written with.
    ///
    /// `NSEvent` hands out more than that — caps lock, the numeric keypad, the
    /// function bit that every arrow key carries — and none of them should
    /// make two presses of the same combination compare unequal.
    static func normalized(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.control, .option, .shift, .command])
    }
}

// MARK: - Storage

extension ListeningHotkey {
    private enum Field {
        static let keyCode = "keyCode"
        static let character = "character"
        static let modifiers = "modifiers"
    }

    /// A property list the settings can hand `UserDefaults`.
    var stored: [String: Any] {
        [
            Field.keyCode: Int(keyCode),
            Field.character: character,
            Field.modifiers: Int(modifiers.rawValue),
        ]
    }

    /// Reads one back, or nothing if the stored value is not one of ours —
    /// which is what a hand-edited defaults domain looks like.
    init?(stored: [String: Any]) {
        guard let keyCode = stored[Field.keyCode] as? Int,
              (0...0xFFFF).contains(keyCode),
              let character = stored[Field.character] as? String,
              let modifiers = stored[Field.modifiers] as? Int else { return nil }

        self.keyCode = UInt16(keyCode)
        self.character = character
        self.modifiers = Self.normalized(NSEvent.ModifierFlags(rawValue: UInt(modifiers)))
    }
}
