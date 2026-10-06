import SwiftUI

/// All motion respects Reduce Motion: animations are skipped and the final
/// state is shown immediately.

/// Stickers "slap on": drop in from 1.7× with a little overshoot.
struct SlapOn: ViewModifier {
    var rotation: Double
    var delay: Double
    var startScale: CGFloat = 1.7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rotation))
            .scaleEffect(reduceMotion || landed ? 1 : startScale)
            .opacity(reduceMotion || landed ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.55).delay(delay)) { landed = true }
            }
    }
}

/// The "Let's lift!" button's periodic jiggle.
struct Jiggle: ViewModifier {
    var period: Double = 3
    var startDelay: Double = 2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    func body(content: Content) -> some View {
        if reduceMotion {
            content.rotationEffect(.degrees(-1))
        } else {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(start) - startDelay
                let (angle, scale) = Jiggle.pose(at: t, period: period)
                content.rotationEffect(.degrees(angle)).scaleEffect(scale)
            }
        }
    }

    /// Keyframes from the mockup's CSS (76%-92% of each cycle).
    static func pose(at t: Double, period: Double) -> (Double, CGFloat) {
        guard t > 0 else { return (-1, 1) }
        let f = t.truncatingRemainder(dividingBy: period) / period
        let keys: [(Double, Double, CGFloat)] = [(0, -1, 1), (0.76, -1, 1), (0.80, -4, 1.03), (0.84, 2.5, 1.03), (0.88, -2.5, 1), (0.92, 0, 1), (1, -1, 1)]
        for i in 1..<keys.count where f <= keys[i].0 {
            let a = keys[i - 1], b = keys[i]
            let u = (f - a.0) / max(b.0 - a.0, 0.0001)
            return (a.1 + (b.1 - a.1) * u, a.2 + (b.2 - a.2) * CGFloat(u))
        }
        return (-1, 1)
    }
}

/// Gentle pulse for the sticker on the start button.
struct Pulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1.1 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true).delay(2)) { on = true }
            }
    }
}

/// Little nudge loop for the doodle arrow.
struct Nudge: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .offset(x: on ? 3 : 0, y: on ? 4 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

/// Cards rising into place (Journal).
struct RiseIn: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .offset(y: reduceMotion || shown ? 0 : 18)
            .opacity(reduceMotion || shown ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func slapOn(rotation: Double = 0, delay: Double = 0, from scale: CGFloat = 1.7) -> some View {
        modifier(SlapOn(rotation: rotation, delay: delay, startScale: scale))
    }
    func jiggle() -> some View { modifier(Jiggle()) }
    func pulse() -> some View { modifier(Pulse()) }
    func nudge() -> some View { modifier(Nudge()) }
    func riseIn(delay: Double) -> some View { modifier(RiseIn(delay: delay)) }

    /// The die-cut sticker drop shadow.
    func stickerShadow() -> some View { shadow(color: Palette.ink.opacity(0.22), radius: 2, y: 2) }
}
