import AppKit

/// What the menu offers where **Start Listening** would go.
///
/// The menu bar icon draws the same mark for unfinished setup as for an engine
/// that failed — both mean dictation cannot happen and only the user can change
/// that — so this is where the two are told apart. It is also the only place
/// the engine's failure is ever seen: nothing else reads the message it
/// records.
enum MenuBarAction: Equatable {
    /// Something setup covers is missing. Its progress, its failures and its
    /// retries are all in that window, so the menu says nothing about them.
    case finishSetup
    /// The engine is down, and the reason it gave.
    case failed(reason: String)
    /// The weights are still coming into memory. Nothing is wrong and there is
    /// nothing to do about it but wait.
    case loading
    /// The ordinary case in always-on listening, active or not.
    case dictate(isActive: Bool)

    /// Hold to talk, with a combination to hold. Not an action: the key is the
    /// only way in and out, and an item that started dictation from the mouse
    /// would leave nothing to release.
    case holdToTalk(combination: String)

    /// Hold to talk with nothing recorded to hold. The one line in this mode
    /// that can be clicked, because it leads somewhere that can fix it.
    case setHotkey

    /// Setup comes first. A missing wake word model fails the engine as surely
    /// as a corrupt one does, and the window that can fetch it back is a better
    /// answer than a **Try Again** that would fail on the same missing file.
    ///
    /// Loading comes last of the three that are not dictation. It is the only
    /// one of them that ends on its own — and it comes before the mode, since
    /// what the user chose says nothing about weights that are not in memory
    /// yet.
    ///
    /// - Parameters:
    ///   - mode: which of the two ways in the user chose. It decides only the
    ///     ordinary line: the three states above it are about the engine, and
    ///     say the same thing in either mode.
    ///   - hotkey: the combination, which hold to talk names in its line and
    ///     always-on listening draws beside its item.
    init(needsSetup: Bool,
         status: EngineStatus,
         failure: String?,
         mode: ListeningMode,
         hotkey: ListeningHotkey?) {
        if needsSetup {
            self = .finishSetup
        } else if status == .error {
            self = .failed(reason: failure ?? MenuBarAction.unexplained)
        } else if status == .loading {
            self = .loading
        } else if mode == .holdToTalk {
            self = hotkey.map { .holdToTalk(combination: $0.displayString) } ?? .setHotkey
        } else {
            self = .dictate(isActive: status.isActive)
        }
    }

    /// What a failure with nothing recorded says. Rare enough to be a bug, and
    /// still better than an empty line above a **Try Again**.
    static let unexplained = "Dictation could not start"

    var title: String {
        switch self {
        case .finishSetup:
            return "Finish Setup…"
        case let .failed(reason):
            return Self.oneLine(reason)
        case .loading:
            return "Loading the model…"
        case let .dictate(isActive):
            return isActive ? "Stop Listening" : "Start Listening"
        case let .holdToTalk(combination):
            return "Hold \(combination) to talk"
        case .setHotkey:
            return "Set a Listening Hotkey…"
        }
    }

    /// The shortcut the item carries, as `NSMenuItem` wants it.
    ///
    /// Only where dictation is on offer. The lines that replace it cannot be
    /// clicked and the hotkey is inert in the states they stand for, so a
    /// combination drawn beside one would promise a way past a wait that has
    /// to be waited out. Hold to talk's line names its combination in the
    /// title instead — a shortcut there would read as something to press.
    ///
    /// A modifier held on its own has no key equivalent to give — the menu has
    /// no way to draw one — so it shows nothing rather than a bare ⌥.
    func shortcut(_ hotkey: ListeningHotkey?) -> (keyEquivalent: String, modifiers: NSEvent.ModifierFlags) {
        guard case .dictate = self, let hotkey, !hotkey.isModifierOnly else { return ("", []) }
        return (hotkey.menuKeyEquivalent, hotkey.modifiers)
    }

    /// A menu item is one line. Sixty characters is what fits before the menu
    /// starts widening to hold a dictated paragraph, or the tail of whatever
    /// CoreML had to say about a model it could not read.
    static func oneLine(_ text: String) -> String {
        text.count > 60 ? String(text.prefix(60)) + "…" : text
    }
}
