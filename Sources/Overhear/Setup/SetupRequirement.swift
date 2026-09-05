import Foundation

/// One of the four things Overhear cannot dictate without.
///
/// The setup window draws a card per case, in the order `allCases` gives them:
/// the two downloads first, because they are the slow ones and the permissions
/// can be granted while they run.
enum SetupRequirement: Hashable, Identifiable, CaseIterable {
    /// A transcription model on disk — whichever one is active.
    case model
    /// The models the cancel word is heard with. The one requirement that
    /// settles itself: nobody chooses these, so the card downloads them rather
    /// than asking.
    case wakeWords
    /// Something macOS has to be asked for.
    case permission(Permission)

    static var allCases: [SetupRequirement] {
        [.model, .wakeWords] + Permission.allCases.map(SetupRequirement.permission)
    }

    var id: String {
        switch self {
        case .model: return "model"
        case .wakeWords: return "wakeWords"
        case let .permission(permission): return permission.id
        }
    }

    /// The card's heading while it is still outstanding. A model card that has
    /// something to name shows the model instead — `SetupCoordinator` decides.
    var title: String {
        switch self {
        case .model: return "Choose a model"
        case .wakeWords: return "Hot word models"
        case let .permission(permission): return permission.title
        }
    }

    var explanation: String {
        switch self {
        case .model:
            return "Download a model that will be used locally on your Mac for the transcription. You can change it later in settings."
        case .wakeWords:
            return "Overhear listens for a hot word to cancel dictation. Its models are downloaded separately from the app, for licensing reasons."
        case let .permission(permission):
            return permission.explanation
        }
    }

    var symbol: String {
        switch self {
        case .model: return "waveform"
        case .wakeWords: return "waveform.badge.mic"
        case .permission(.microphone): return "mic"
        case .permission(.textInsertion): return "keyboard"
        }
    }
}
