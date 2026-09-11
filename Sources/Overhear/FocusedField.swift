import AppKit
import ApplicationServices

/// What surrounds the caret in whichever application is focused, read over the
/// Accessibility API.
///
/// Insertion is a paste, so nothing about it says where it landed. The field
/// itself is the only thing that knows, and it is asked at the moment of the
/// insertion rather than remembered from the last one — a user who types a
/// comma or moves the caret between utterances gets the spacing their caret
/// asks for. `Specs/Spacing.md`.
///
/// Everything here is best effort. A field that will not answer — a password
/// field, a terminal, an editor that draws its own text — yields
/// `CaretContext.unknown`, and the transcription goes in as it did before any
/// of this existed.
@MainActor
enum FocusedField {
    /// How long to wait on the focused application before giving up on it.
    ///
    /// The default is six seconds, which an unresponsive application would
    /// spend hanging the insertion. Nothing here is worth a visible stall: a
    /// read that takes this long has already cost more than the space it would
    /// have added.
    private static let timeout: Float = 0.25

    static func caretContext() -> CaretContext {
        if let context = read() { return context }

        // Nothing answered at all. A Chromium window is the usual reason: Chrome
        // and every Electron app build their accessibility tree only once a
        // client asks for it by name, and until then a window full of text
        // fields looks like one opaque group from out here. Asking is the whole
        // fix, and it is asked once per application — see `turnOnAccessibility`.
        guard turnOnAccessibility() else { return .unknown }
        return read() ?? .unknown
    }

    /// `nil` when the field would not say where the caret is, as opposed to
    /// `CaretContext.unknown`, which is an answer: a caret with nothing around
    /// it. Only the first is worth turning an application's accessibility on
    /// for.
    private static func read() -> CaretContext? {
        guard let element = focusedElement() else { return nil }
        guard !isSecure(element) else { return .unknown }
        guard let range = selectedRange(of: element) else { return nil }

        let start = range.location
        let end = range.location + range.length
        guard start >= 0, end >= start else { return .unknown }

        // Ask for the two characters themselves where the field can answer
        // that. The alternative copies the whole document out of the
        // application, which is the difference between reading two characters
        // and reading a novel every time someone finishes a sentence.
        if start > 0 {
            guard let before = character(of: element, at: start - 1) else {
                // The field has text before the caret and would not hand it
                // over one character at a time, so it does not support this.
                return contextFromWholeValue(of: element, start: start, end: end)
            }
            return CaretContext(before: before, after: character(of: element, at: end))
        }

        // With nothing before the caret there is nothing to probe with, so a
        // missing character after it could be the end of the field or a field
        // that will not answer. Reading the value settles which.
        if let after = character(of: element, at: end) {
            return CaretContext(before: nil, after: after)
        }
        return contextFromWholeValue(of: element, start: start, end: end)
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)

        guard let value = copy(kAXFocusedUIElementAttribute, from: system),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }

        // swiftlint:disable:next force_cast
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    /// A password field answers the same questions as any other text field,
    /// and what it hands back is a row of bullets. Spacing off that would be
    /// spacing off a character the user never typed, so the field is left to
    /// take the text as transcribed.
    private static func isSecure(_ element: AXUIElement) -> Bool {
        guard let role = copy(kAXRoleAttribute, from: element) as? String else { return false }
        // Spelled out: `NSAccessibility.Role` has a case for most roles and
        // none for this one.
        return role == "AXSecureTextField"
    }

    /// Where the insertion will land. A selection is replaced by the paste, so
    /// its two ends are what the text will sit between.
    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value = copy(kAXSelectedTextRangeAttribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        var range = CFRange()
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func character(of element: AXUIElement, at index: Int) -> Character? {
        var range = CFRange(location: index, length: 1)
        guard let requested = AXValueCreate(.cfRange, &range) else { return nil }

        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            requested,
            &value
        )
        guard result == .success else { return nil }
        return (value as? String)?.first
    }

    /// The fallback for fields that hold their text but will not serve a range
    /// of it. Ranges arrive in UTF-16 units, which is what the API counts in.
    private static func contextFromWholeValue(of element: AXUIElement, start: Int, end: Int) -> CaretContext? {
        guard let value = copy(kAXValueAttribute, from: element),
              let text = value as? String else { return nil }

        let units = text.utf16.count
        guard start <= units, end <= units else { return .unknown }

        let startIndex = String.Index(utf16Offset: start, in: text)
        let endIndex = String.Index(utf16Offset: end, in: text)

        return CaretContext(
            before: startIndex > text.startIndex ? text[text.index(before: startIndex)] : nil,
            after: endIndex < text.endIndex ? text[endIndex] : nil
        )
    }

    /// Applications already asked to switch their accessibility on, so the
    /// question is put once per launch rather than once per utterance.
    private static var asked: Set<pid_t> = []

    /// Asks the focused application to build the accessibility tree it has been
    /// keeping to itself.
    ///
    /// `AXManualAccessibility` is Chromium's own switch, and setting it is what
    /// assistive software does — Chromium ignores the ordinary signs of being
    /// read, deliberately, because maintaining the tree costs it memory in every
    /// renderer. Applications that are not Chromium ignore the attribute, so
    /// this is a question that answers itself.
    ///
    /// Returns whether it is worth reading again. The tree is built after the
    /// attribute is set rather than during, so the read that follows can still
    /// come back empty and the utterance that prompted all this goes in
    /// unspaced. The next one lands in a window that answers.
    private static func turnOnAccessibility() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              !asked.contains(pid) else { return false }
        asked.insert(pid)

        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        return AXUIElementSetAttributeValue(
            application,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        ) == .success
    }

    private static func copy(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
