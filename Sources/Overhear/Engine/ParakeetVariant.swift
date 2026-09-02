import FluidAudio
import Foundation

/// The one place that knows FluidAudio's names for the models Overhear offers.
///
/// `TranscriptionModel.variant` holds the directory name FluidAudio lays a model
/// out in, so the catalogue and the library agree on one string rather than two
/// that have to be kept in step.
enum ParakeetVariant: CaseIterable {
    case v2
    case v3

    /// The encoder build to fetch, check for and load.
    ///
    /// A single constant rather than three call sites choosing for themselves:
    /// `download`, `modelsExist` and `load` each take a precision and name a
    /// different encoder file per value, so disagreement means the service
    /// reports a model downloaded that the transcriber then cannot find.
    static let encoderPrecision: ParakeetEncoderPrecision = .int8

    init?(variant: String) {
        guard let match = ParakeetVariant.allCases.first(where: { $0.variant == variant }) else {
            return nil
        }
        self = match
    }

    init?(model: TranscriptionModel) {
        guard model.engine == .parakeet else { return nil }
        self.init(variant: model.variant)
    }

    var version: AsrModelVersion {
        switch self {
        case .v2: return .v2
        case .v3: return .v3
        }
    }

    private var repo: Repo {
        switch self {
        case .v2: return .parakeetV2
        case .v3: return .parakeetV3
        }
    }

    /// The directory FluidAudio puts this model in, taken from the library
    /// rather than spelled out here — a repository renamed upstream would
    /// otherwise silently re-download into a directory nothing reads.
    var variant: String { repo.folderName }
}
