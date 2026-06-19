import AppKit
import Carbon.HIToolbox

enum TextInjector {
    static func inject(text: String) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulatePaste()

        if let previous = previousContents {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    private static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}
