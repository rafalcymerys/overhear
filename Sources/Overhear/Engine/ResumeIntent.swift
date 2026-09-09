import Foundation

/// The intention to carry on dictating across a device change.
///
/// Held only by a device going away under someone who was dictating, and
/// dropped the moment they decide for themselves — starting, stopping and
/// letting go of a held key all answer the question this is keeping open.
struct ResumeIntent {
    /// How long a device change may take before dictation stops meaning to come
    /// back.
    ///
    /// Long enough for AirPods to hand over or an interface to be replugged,
    /// short enough that a Mac left alone never opens its microphone at
    /// whatever hour the device happens to reappear. Injected so a test can
    /// watch it lapse without waiting out half a minute.
    let window: TimeInterval

    private var deadline: Date?

    init(window: TimeInterval) {
        self.window = window
    }

    mutating func expect(now: Date = Date()) {
        deadline = now.addingTimeInterval(window)
    }

    mutating func cancel() {
        deadline = nil
    }

    /// Whether dictation should pick up again. True at most once per intention,
    /// and false once the window has lapsed.
    mutating func claim(now: Date = Date()) -> Bool {
        guard let deadline else { return false }
        self.deadline = nil
        return now < deadline
    }
}
