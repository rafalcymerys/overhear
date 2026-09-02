import SwiftUI

/// The live mark — a single dot, 2.8x its own size at the ring's peak. Every state
/// is the same circle in a different colour and motion. Shared by the menu bar icon
/// and the overlay, so the two can never drift apart.
private let markAccent = Color(red: 1.0, green: 0.58, blue: 0.0)

enum MarkState {
    case idle
    case listening
    case hearing
    case transcribing
    case cancelled

    init(status: EngineStatus, showCancelled: Bool) {
        if showCancelled {
            self = .cancelled
            return
        }
        switch status {
        case .ready: self = .listening
        case .listening: self = .hearing
        case .transcribing: self = .transcribing
        default: self = .idle
        }
    }
}

struct LiveMark: View {
    var state: MarkState
    var size: CGFloat = 7

    @Environment(\.colorScheme) private var colorScheme

    /// White at full strength on a dark ground, black on a light one. Resolved to a
    /// concrete colour rather than left semantic, so it can be interpolated.
    private var neutral: Color {
        colorScheme == .dark ? .white : .black
    }

    private var markColor: Color {
        switch state {
        case .idle: return neutral.opacity(0.4)
        case .listening: return neutral
        case .hearing, .transcribing: return markAccent
        case .cancelled: return .red
        }
    }

    var body: some View {
        ZStack {
            switch state {
            case .idle, .listening:
                MarkDot(size: size)
            case .hearing:
                HearingMark(size: size)
            case .transcribing:
                TranscribingMark(size: size)
            case .cancelled:
                CancelledMark(size: size)
            }
        }
        // The colour is carried by the container, not the individual states, so a
        // change of state swaps the motion underneath a single crossfading tint.
        .foregroundStyle(markColor)
        .animation(.easeInOut(duration: 0.3), value: markColor)
    }
}

/// Fills with the inherited foreground style — the colour comes from `LiveMark`.
private struct MarkDot: View {
    var size: CGFloat

    var body: some View {
        Circle()
            .frame(width: size, height: size)
    }
}

/// Both layers of the mark share one clock, so the core's peak and the ring's
/// mid-flight stay permanently in phase.
private struct MarkFrame {
    var coreScale: CGFloat
    var ringScale: CGFloat
    var ringOpacity: Double
}

/// Hearing — the sonar ping: a ring leaves the core fast, decelerates into the
/// fade, then rests invisibly before the next one.
private struct HearingMark: View {
    var size: CGFloat

    var body: some View {
        KeyframeAnimator(
            initialValue: MarkFrame(coreScale: 1, ringScale: 1, ringOpacity: 0.4),
            repeating: true
        ) { frame in
            ZStack {
                MarkDot(size: size)
                    .scaleEffect(frame.ringScale)
                    .opacity(frame.ringOpacity)
                MarkDot(size: size)
                    .scaleEffect(frame.coreScale)
            }
        } keyframes: { _ in
            // Ring: 1x -> 2.8x on an ease-out cubic over 1.96 s, then a silent
            // 0.84 s hold. The rest between pings is what keeps it from reading
            // as busy.
            KeyframeTrack(\.ringScale) {
                CubicKeyframe(2.8, duration: 1.96, startVelocity: 3 * (2.8 - 1.0) / 1.96, endVelocity: 0)
                LinearKeyframe(2.8, duration: 0.84)
            }
            KeyframeTrack(\.ringOpacity) {
                CubicKeyframe(0, duration: 1.96, startVelocity: 3 * (0 - 0.4) / 1.96, endVelocity: 0)
                LinearKeyframe(0, duration: 0.84)
            }
            // Core: a barely perceptible +-10% breath across the same 2.8 s.
            KeyframeTrack(\.coreScale) {
                CubicKeyframe(1.1, duration: 1.4, startVelocity: 0, endVelocity: 0)
                CubicKeyframe(1.0, duration: 1.4, startVelocity: 0, endVelocity: 0)
            }
        }
    }
}

/// Transcribing — the ping run backwards: a ring gathers in from the outside and
/// lands on the core, which pops as it absorbs it. Faster than the ping, so the
/// two never read as the same state.
private struct TranscribingMark: View {
    var size: CGFloat

    var body: some View {
        KeyframeAnimator(
            initialValue: MarkFrame(coreScale: 1, ringScale: 2.6, ringOpacity: 0),
            repeating: true
        ) { frame in
            ZStack {
                MarkDot(size: size)
                    .scaleEffect(frame.ringScale)
                    .opacity(frame.ringOpacity)
                MarkDot(size: size)
                    .scaleEffect(frame.coreScale)
            }
        } keyframes: { _ in
            // Ring: 2.6x -> 1x, accelerating inward so the arrival is the accent.
            KeyframeTrack(\.ringScale) {
                CubicKeyframe(1.0, duration: 0.8, startVelocity: 0, endVelocity: 2 * (1.0 - 2.6) / 0.8)
                LinearKeyframe(1.0, duration: 0.3)
            }
            KeyframeTrack(\.ringOpacity) {
                LinearKeyframe(0.45, duration: 0.25)
                LinearKeyframe(0.45, duration: 0.4)
                LinearKeyframe(0, duration: 0.15)
                LinearKeyframe(0, duration: 0.3)
            }
            // Core: still until the ring lands, then a single soft pop.
            KeyframeTrack(\.coreScale) {
                LinearKeyframe(1.0, duration: 0.7)
                CubicKeyframe(1.18, duration: 0.15, startVelocity: 0, endVelocity: 0)
                CubicKeyframe(1.0, duration: 0.25, startVelocity: 0, endVelocity: 0)
            }
        }
    }
}

/// Cancelled — the same dot in red, shaken off.
private struct CancelledMark: View {
    var size: CGFloat

    @State private var animating = false

    var body: some View {
        MarkDot(size: size)
            .offset(x: animating ? 3 : -3)
            .animation(
                .easeInOut(duration: 0.08)
                    .repeatForever(autoreverses: true),
                value: animating
            )
            .onAppear { animating = true }
    }
}
