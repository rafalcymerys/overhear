import Foundation

/// What the listening hotkey does, and so how a dictation session begins and
/// ends.
///
/// The mode is not one of the settings the engine is built from — it decides
/// who starts and stops a session, not what a session does — so changing it
/// reloads nothing.
enum ListeningMode: String, CaseIterable, Identifiable {
    /// The combination toggles: one press starts listening, the next stops it,
    /// and the menu offers the same two.
    case alwaysOn

    /// The combination is held: the press starts a session and the release
    /// ends it, transcribing what was said rather than discarding it. The key
    /// is the only way in and out, so the menu offers no toggle.
    case holdToTalk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alwaysOn: return "Always-on listening"
        case .holdToTalk: return "Hold to talk"
        }
    }

    /// What the settings pane says under the option.
    var explanation: String {
        switch self {
        case .alwaysOn:
            return "Overhear keeps listening in the background. Use the menu or the hotkey to turn listening on and off."
        case .holdToTalk:
            return "Overhear listens only while you hold the hotkey. Letting go transcribes what you said."
        }
    }
}
