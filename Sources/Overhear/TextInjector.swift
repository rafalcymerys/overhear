import AppKit
import Carbon.HIToolbox

protocol TextInjecting {
    func inject(text: String)
}

/// Pastes text by putting it on the general pasteboard, simulating Cmd+V, then
/// restoring whatever was on the pasteboard before.
///
/// `performPaste` and `restoreDelay` exist so tests can exercise the clipboard
/// save/restore without posting a synthetic Cmd+V into whichever application
/// happens to be focused.
struct PasteboardTextInjector: TextInjecting {
    var pasteboard: NSPasteboard = .general
    var performPaste: () -> Void = PasteboardTextInjector.simulatePaste
    var restoreDelay: TimeInterval = 0.3

    func inject(text: String) {
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        performPaste()

        if let previous = previousContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}
