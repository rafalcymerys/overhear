import AppKit
import Carbon.HIToolbox

protocol TextInjecting {
    /// On the main actor: it reads a setting, reads the focused field, and
    /// drives the pasteboard, all of which belong there. Both call sites are
    /// already there too.
    @MainActor func inject(text: String)
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

    /// Whether to separate the insertion from what is already in the field,
    /// whether to case its front to suit the sentence, and what is around the
    /// caret when either of them asks.
    ///
    /// All three are read at the moment of the insertion: the settings so that
    /// toggling one applies to the next utterance rather than to the next
    /// launch, the surroundings so that both rules follow the caret rather than
    /// what was inserted last. Closures so tests can place a caret without an
    /// application to read it out of.
    var spacesInsertedText: @MainActor () -> Bool = { AppSettings.shared.spaceInsertedText }
    var matchesSentenceCase: @MainActor () -> Bool = { AppSettings.shared.matchSentenceCase }
    var caretContext: @MainActor () -> CaretContext = { FocusedField.caretContext() }

    func inject(text: String) {
        let spacing = spacesInsertedText()
        let casing = matchesSentenceCase()
        // One read for both rules. Asking the focused application twice would
        // cost twice as much for the same two answers, and a caret that moved
        // between the reads would have them disagree.
        let context = spacing || casing ? caretContext() : .unknown

        // Cased before it is spaced, since casing works off the front of the
        // transcription and spacing would put a space in front of it. Both
        // before the pasteboard rather than typed around the paste: what goes
        // in is one insertion, which is one undo.
        var text = text
        if casing { text = InsertionCasing.apply(to: text, in: context) }
        if spacing { text = InsertionSpacing.apply(to: text, in: context) }

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
