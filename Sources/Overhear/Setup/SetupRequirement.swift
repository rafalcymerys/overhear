import Foundation

/// One of the three things Overhear cannot dictate without.
///
/// The setup window draws a card per case, in the order `allCases` gives them:
/// the model first, because its download is the slow one and the permissions
/// can be granted while it runs.
enum SetupRequirement: Hashable, Identifiable, CaseIterable {
    /// A transcription model on disk — whichever one is active.
    case model
    /// Something macOS has to be asked for.
    case permission(Permission)

    static var allCases: [SetupRequirement] {
        [.model] + Permission.allCases.map(SetupRequirement.permission)
    }

    var id: String {
        switch self {
        case .model: return "model"
        case let .permission(permission): return permission.id
        }
    }

    /// The card's heading while it is still outstanding. A model card that has
    /// something to name shows the model instead — `SetupCoordinator` decides.
    var title: String {
        switch self {
        case .model: return "Choose a model"
        case let .permission(permission): return permission.title
        }
    }

    var explanation: String {
        switch self {
        case .model:
            return "Download a model that will be used locally on your Mac for the transcription. You can change it later in settings."
        case let .permission(permission):
            return permission.explanation
        }
    }

    var symbol: String {
        switch self {
        case .model: return "waveform"
        case .permission(.microphone): return "mic"
        case .permission(.textInsertion): return "keyboard"
        }
    }
}
