import Combine
import Foundation

/// What a press means, and who ends a session.
///
/// `ListeningHotkeyMonitor` reports a press and a release and nothing about
/// what either is for. This is where the mode decides: always-on listening
/// toggles on the press and ignores the release; hold to talk starts a session
/// on the press and ends it on the release. Those two endings are not the same
/// one — stopping discards and a release keeps — which is the whole reason the
/// distinction is worth a type.
///
/// Either way nothing happens unless the engine is idle or dictating, so the
/// hotkey is inert while the model loads and after a failure, in both modes,
/// exactly as the menu is.
@MainActor
final class ListeningController {
    private let engine: EngineController
    private let appState: AppState
    private let settings: AppSettings
    private let monitor: ListeningHotkeyMonitor

    private var hotkeyObservation: AnyCancellable?
    private var modeObservation: AnyCancellable?

    /// Set while something is waiting for the engine to reach idle so it can
    /// start dictating — a launch, or the far side of a model swap.
    private var idleObservation: AnyCancellable?

    /// Whether a hold-to-talk session is running: the key went down over an
    /// idle engine and has not come up.
    ///
    /// What keeps a release from ending a session it did not start — the one
    /// begun before the mode changed, or the one stopped from the overlay
    /// while the key was still down.
    private var isHolding = false

    init(engine: EngineController,
         appState: AppState,
         settings: AppSettings? = nil,
         monitor: ListeningHotkeyMonitor? = nil) {
        self.engine = engine
        self.appState = appState
        // Resolved here rather than as default arguments: both are main actor
        // isolated, which a default argument is not.
        self.settings = settings ?? .shared
        self.monitor = monitor ?? .shared
    }

    /// Watch for the hotkey, and keep watching for whatever it is changed to.
    func start() {
        monitor.onPress = { [weak self] in
            self?.pressed()
        }
        monitor.onRelease = { [weak self] in
            self?.released()
        }
        // A key that will never come back up ends the session rather than
        // leaving one running with nobody holding it. It ends as stopping
        // would, not as a release does: nobody said what they were saying was
        // finished, and the screen it would have been pasted into is locked.
        monitor.onLostPress = { [weak self] in
            self?.stopDictating()
        }
        registerHotkey()

        hotkeyObservation = settings.$listeningHotkey
            .dropFirst()
            .sink { [weak self] hotkey in
                Task { @MainActor in
                    self?.monitor.update(hotkey)
                }
            }
        modeObservation = settings.$listeningMode
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.modeChanged()
                }
            }
    }

    /// Register the stored combination, building the tap if there was no
    /// Accessibility to build one with before.
    func registerHotkey() {
        monitor.update(settings.listeningHotkey)
    }

    /// Start or stop, as **Start Listening** and **Stop Listening** do.
    func toggle() {
        if appState.status.isActive {
            stopDictating()
        } else if appState.status == .idle {
            engine.activate()
        }
    }

    /// Stop and discard, from wherever stopping is asked for that is not a
    /// release: the menu, the overlay's button, and a key that will never come
    /// back up.
    func stopDictating() {
        isHolding = false
        engine.deactivate()
    }

    /// Start dictating as soon as the engine reaches idle — for the launch that
    /// is set to listen, and for the model swap that interrupted a session.
    ///
    /// Never in hold to talk, where **Start listening on launch** has nothing
    /// to act on: there would be no key held, and no **Stop Listening** to
    /// reach the session with.
    func listenWhenIdle() {
        guard settings.listeningMode == .alwaysOn else { return }
        idleObservation = appState.$status
            .first { $0 == .idle }
            .sink { [weak self] _ in
                self?.engine.activate()
                self?.idleObservation = nil
            }
    }

    func cancelPendingStart() {
        idleObservation = nil
    }

    /// Forget a hold in progress without ending the session, for a caller that
    /// is about to take the engine down anyway.
    ///
    /// The audio goes with the engine, and a session resumed under a key that
    /// is already down would have no release left to end it.
    func forgetTheHold() {
        isHolding = false
    }

    private func pressed() {
        switch settings.listeningMode {
        case .alwaysOn:
            toggle()
        case .holdToTalk:
            beginHold()
        }
    }

    private func released() {
        guard settings.listeningMode == .holdToTalk, isHolding else { return }
        isHolding = false
        // Not `deactivate()`. The release ends the batch rather than discarding
        // it: what was said up to here is transcribed and inserted, which is
        // where hold to talk parts company with **Stop Listening**.
        engine.finish()
    }

    /// Start a session for as long as the key is held.
    ///
    /// Only from idle, which is the same rule the toggle follows — so a press
    /// during the load, after a failure, or while the batch from the last hold
    /// is still transcribing does nothing at all.
    private func beginHold() {
        guard appState.status == .idle else { return }
        isHolding = true
        engine.activate()
    }

    /// End whatever is running when the mode changes.
    ///
    /// The session belonged to the mode that has just been replaced. Left
    /// running it would be one no key could end: the release ends only what a
    /// hold started, and hold to talk offers no **Stop Listening** to reach it
    /// with. Ending it either way is one rule rather than two, and it leaves
    /// nothing running that the mode the user has just chosen would not have
    /// started.
    ///
    /// Nothing is reloaded: the mode is not one of the settings the engine is
    /// built from.
    private func modeChanged() {
        // A launch or a model swap that was waiting for idle to start dictating
        // was waiting on behalf of the mode that has just gone.
        cancelPendingStart()
        isHolding = false
        guard appState.status.isActive else { return }
        engine.deactivate()
    }
}
