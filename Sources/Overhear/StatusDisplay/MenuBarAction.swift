import Foundation

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
    /// The ordinary case, active or not.
    case dictate(isActive: Bool)

    /// Setup comes first. A missing wake word model fails the engine as surely
    /// as a corrupt one does, and the window that can fetch it back is a better
    /// answer than a **Try Again** that would fail on the same missing file.
    ///
    /// Loading comes last of the three that are not dictation. It is the only
    /// one of them that ends on its own.
    init(needsSetup: Bool, status: EngineStatus, failure: String?) {
        if needsSetup {
            self = .finishSetup
        } else if status == .error {
            self = .failed(reason: failure ?? MenuBarAction.unexplained)
        } else if status == .loading {
            self = .loading
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
        }
    }

    /// A menu item is one line. Sixty characters is what fits before the menu
    /// starts widening to hold a dictated paragraph, or the tail of whatever
    /// CoreML had to say about a model it could not read.
    static func oneLine(_ text: String) -> String {
        text.count > 60 ? String(text.prefix(60)) + "…" : text
    }
}
