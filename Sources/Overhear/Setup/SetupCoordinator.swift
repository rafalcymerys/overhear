import Combine
import Foundation

/// What the setup window is for: whether each requirement is met, which card is
/// open, and the one thing each card offers to do about it.
///
/// Owns no window. `AppDelegate` watches `isComplete` to decide whether to put
/// the window up and when to bring the engine up; the view reads the rest.
///
/// Nothing here downloads on its own. A fresh install shows the preselected
/// model and waits to be told, which is the difference between this and the
/// first launch it replaces.
@MainActor
final class SetupCoordinator: ObservableObject {
    let permissions: PermissionsService
    let models: TranscriptionModelService
    private let settings: AppSettings

    /// Every requirement is met, so the window has nothing left to do.
    @Published private(set) var isComplete: Bool = false

    /// Which model the card's control shows. It starts on the active model, so
    /// a fresh install offers Whisper Base and an install whose weights went
    /// missing offers the model that was lost rather than the default.
    @Published var chosenModelID: String

    /// Cards the user opened or shut by hand. These win over what setup would
    /// have shown, until the requirement is settled and the entry is dropped.
    @Published private var manualExpansion: [SetupRequirement: Bool] = [:]

    private var observations: Set<AnyCancellable> = []

    /// - Parameters:
    ///   - models: what is on disk. Resolved in the body rather than as a
    ///     default argument, which cannot reach a main actor isolated
    ///     singleton.
    init(permissions: PermissionsService,
         models: TranscriptionModelService? = nil,
         settings: AppSettings? = nil) {
        let models = models ?? .shared
        let settings = settings ?? .shared
        self.permissions = permissions
        self.models = models
        self.settings = settings
        self.chosenModelID = settings.activeModelID

        // The emitted values, not the properties: `@Published` fires from
        // `willSet`, so reading the objects here would give the state before
        // whatever woke this up.
        Publishers.CombineLatest3(permissions.$states, models.$downloadedIDs, settings.$activeModelID)
            .sink { [weak self] states, downloaded, activeID in
                self?.evaluate(states: states, downloaded: downloaded, activeID: activeID)
            }
            .store(in: &observations)
    }

    // MARK: - What is left to do

    func isSatisfied(_ requirement: SetupRequirement) -> Bool {
        switch requirement {
        case .model:
            return models.isDownloaded(settings.activeModel)
        case let .permission(permission):
            return permissions.state(of: permission) == .granted
        }
    }

    /// Something is already happening to this requirement, so it is neither
    /// finished nor waiting on the user.
    func isBusy(_ requirement: SetupRequirement) -> Bool {
        guard case .model = requirement else { return false }
        return models.isDownloading(chosenModel) || failure != nil
    }

    /// The card the window would open on its own: the first one that is
    /// outstanding and not already busy.
    ///
    /// A download in progress is skipped deliberately — the point of the
    /// checklist is that the permissions can be granted while it runs, which
    /// they cannot be if the model card holds the user's place in the queue.
    var firstNeedingAttention: SetupRequirement? {
        SetupRequirement.allCases.first { !isSatisfied($0) && !isBusy($0) }
    }

    func isExpanded(_ requirement: SetupRequirement) -> Bool {
        if let manual = manualExpansion[requirement] { return manual }
        guard !isSatisfied(requirement) else { return false }
        if isBusy(requirement) { return true }
        return requirement == firstNeedingAttention
    }

    func toggle(_ requirement: SetupRequirement) {
        manualExpansion[requirement] = !isExpanded(requirement)
    }

    /// Re-read what macOS and the disk say. Called when the window opens, where
    /// either could have changed while Overhear was not looking.
    func refresh() {
        permissions.refresh()
        models.refresh()
    }

    // MARK: - The model card

    var chosenModel: TranscriptionModel {
        ModelCatalog.model(id: chosenModelID) ?? ModelCatalog.defaultModel
    }

    /// The model card's heading: what was settled if anything was, and the
    /// invitation otherwise.
    var modelCardTitle: String {
        if isSatisfied(.model) { return settings.activeModel.displayName }
        if isBusy(.model) { return chosenModel.displayName }
        return SetupRequirement.model.title
    }

    /// How far the chosen model's download has got, or nothing when none is
    /// running.
    var downloadProgress: Double? {
        models.progress[chosenModelID]
    }

    /// Why the chosen model's download failed, if it did.
    var failure: String? {
        models.failures[chosenModelID]
    }

    /// The choice is fixed while its download runs — cancelling first puts it
    /// back, which is also the only way to abandon a download half done.
    var canChooseModel: Bool {
        downloadProgress == nil && failure == nil
    }

    /// Fetch the chosen model and make it the active one.
    ///
    /// Activation waits for the bytes: a model that is set active before it is
    /// on disk would leave the engine loading something that isn't there if the
    /// user cancelled or the download failed.
    func download() {
        let model = chosenModel
        guard !models.isDownloading(model) else { return }

        // Already on disk — the user picked something they had, so there is
        // nothing to fetch and activating it is the whole of the step.
        guard !models.isDownloaded(model) else {
            models.activate(model)
            return
        }

        models.startDownload(model)
        Task { [weak self] in
            await self?.models.waitForDownload(of: model)
            guard let self, self.models.isDownloaded(model) else { return }
            self.models.activate(model)
        }
    }

    func cancelDownload() {
        models.cancelDownload(chosenModel)
    }

    /// Give up on the model that failed and go back to the picker, which is
    /// what someone does after choosing 1.6 GB over a bad connection.
    func chooseAnotherModel() {
        models.clearFailure(chosenModel)
    }

    // MARK: - The permission cards

    func request(_ permission: Permission) {
        permissions.request(permission)
    }

    /// What the button on a permission card says, which depends on whether
    /// macOS will still show its own dialog.
    func buttonTitle(for permission: Permission) -> String {
        permissions.nextRequest(for: permission) == .systemDialog
            ? permission.buttonTitle
            : "Open System Settings"
    }

    // MARK: - Bookkeeping

    private func evaluate(states: [Permission: PermissionState],
                          downloaded: Set<String>,
                          activeID: String) {
        // Read from what was emitted rather than from `isSatisfied`, which
        // would ask the objects that are mid-assignment and get the state
        // before this.
        func settled(_ requirement: SetupRequirement) -> Bool {
            switch requirement {
            case .model: return downloaded.contains(activeID)
            case let .permission(permission): return states[permission] == .granted
            }
        }

        isComplete = SetupRequirement.allCases.allSatisfy(settled)

        // A card the user opened by hand goes back to being the window's
        // business once it is settled, so a finished requirement collapses
        // rather than staying open on a decision already made.
        for requirement in SetupRequirement.allCases where settled(requirement) {
            manualExpansion[requirement] = nil
        }
    }
}
