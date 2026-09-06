import AppKit

/// The combinations macOS has already taken — Cmd+Space and the rest of the
/// keyboard shortcuts in System Settings.
///
/// Registering one of them is not an error anyone reports: the event tap sits
/// ahead of the app but behind the window server's own bindings, so the
/// system's shortcut wins and Overhear's does nothing, silently. Better to
/// refuse the combination while the user is still looking at the recorder.
///
/// Read from `com.apple.symbolichotkeys`, which is where System Settings keeps
/// them: each entry carries whether it is enabled and a `parameters` triple of
/// character, key code and modifier mask — the mask in `NSEvent`'s own raw
/// values.
struct SystemShortcuts {
    private struct Combination: Hashable {
        let keyCode: UInt16
        let modifiers: UInt
    }

    private let taken: Set<Combination>

    /// What the recorder asks. Reads the live domain, so a shortcut the user
    /// turned off in System Settings is not treated as taken.
    static var current: SystemShortcuts {
        SystemShortcuts(symbolicHotkeys: UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys") ?? [:])
    }

    init(symbolicHotkeys: [String: Any]) {
        var taken: Set<Combination> = []
        for entry in symbolicHotkeys.values {
            guard let entry = entry as? [String: Any],
                  entry["enabled"] as? Bool == true,
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Any],
                  parameters.count >= 3,
                  let keyCode = parameters[1] as? Int,
                  // -1 where the shortcut is a modifier chord with no key of
                  // its own, which is not a thing this can compare against.
                  (0...0xFFFF).contains(keyCode),
                  let modifiers = parameters[2] as? Int else { continue }

            let flags = ListeningHotkey.normalized(NSEvent.ModifierFlags(rawValue: UInt(modifiers)))
            taken.insert(Combination(keyCode: UInt16(keyCode), modifiers: flags.rawValue))
        }
        self.taken = taken
    }

    func isTaken(_ hotkey: ListeningHotkey) -> Bool {
        // A modifier on its own is never one of these: every entry in the
        // domain names a key.
        guard !hotkey.isModifierOnly else { return false }
        return taken.contains(Combination(keyCode: hotkey.keyCode, modifiers: hotkey.modifiers.rawValue))
    }
}
