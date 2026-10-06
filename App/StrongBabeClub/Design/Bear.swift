import SwiftUI
import WorkoutCore

/// The line-art animal (bear by default) that acts out the day's lift: one animation per lift,
/// driven by a 2.6 s loop over a tiny 2D skeleton (knee and elbow solved
/// with two-bone IK). Chunky outlined limbs. Frozen in the start pose under
/// Reduce Motion.
struct BearView: View {
    var lift: Lift
    var size: CGFloat = 112
    var fill: Color? = nil
    /// Fixed animation phase (0...1) for galleries/previews; nil = animate.
    var frozenAt: Double?
    /// Override; otherwise the animal chosen in Settings.
    var animal: Animal?
    @AppStorage(Animal.storageKey) private var chosen: Animal = .bear
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var current: Animal { animal ?? chosen }
    /// Only the bear uses the card's paper colour; others keep their fur.
    var paper: Color? { current == .bear ? (fill ?? Palette.paper) : nil }

    static let period = 2.6

    var body: some View {
        Group {
            if let t = frozenAt ?? (reduceMotion ? 0 : nil) {
                LifterCanvas(pose: BearPose.pose(for: lift, t: t), skin: current.skin, paperOverride: paper)
            } else {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
                    LifterCanvas(pose: BearPose.pose(for: lift, t: t), skin: current.skin, paperOverride: paper)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Line-art \(current.rawValue) doing a \(lift.displayName.lowercased())")
    }
}

/// Key pose values, in the 120 × 120 drawing space (y grows down; the bear
/// faces right). The bar is placed relative to the shoulder.
struct BearKey {
    var t: Double
    var hipX: CGFloat
    var hipY: CGFloat
    /// Torso lean from vertical, degrees (positive = forward).
    var lean: CGFloat
    /// Heels up (triple extension), points.
    var heel: CGFloat = 0
    /// Shoulder shrug, points.
    var shrug: CGFloat = 0
    var barDX: CGFloat
    var barDY: CGFloat
    /// Elbow bend side: +1 forward/down, -1 back/up.
    var elbow: CGFloat = 1
}

struct BearPose: Equatable {
    var ankle: CGPoint
    var toe: CGPoint
    var knee: CGPoint
    var hip: CGPoint
    var shoulder: CGPoint
    var head: CGPoint
    var lean: CGFloat
    var elbow: CGPoint
    var hand: CGPoint
    var bar: CGPoint

    static let shin: CGFloat = 19, thigh: CGFloat = 19, torso: CGFloat = 26, upperArm: CGFloat = 14.5, forearm: CGFloat = 14.5
    static let groundAnkle = CGPoint(x: 56, y: 103)

    // Common bar positions relative to the shoulder.
    static let hang = (dx: CGFloat(1), dy: CGFloat(27.5))
    static let frontRack = (dx: CGFloat(10), dy: CGFloat(0))
    static let backRack = (dx: CGFloat(-9), dy: CGFloat(-2))
    static let overhead = (dx: CGFloat(-3), dy: CGFloat(-28.8))
    static let standHip = (x: CGFloat(56), y: CGFloat(65.5))

    static func keys(for lift: Lift) -> [BearKey] {
        let s = standHip
        switch lift {
        case .backSquat:
            let b = backRack
            return [BearKey(t: 0, hipX: s.x, hipY: s.y, lean: 4, barDX: b.dx, barDY: b.dy, elbow: -1),
                    BearKey(t: 0.4, hipX: 42, hipY: 84, lean: 40, barDX: b.dx, barDY: b.dy, elbow: -1),
                    BearKey(t: 0.5, hipX: 42, hipY: 84, lean: 40, barDX: b.dx, barDY: b.dy, elbow: -1),
                    BearKey(t: 0.9, hipX: s.x, hipY: s.y, lean: 4, barDX: b.dx, barDY: b.dy, elbow: -1)]
        case .frontSquat:
            let b = frontRack
            return [BearKey(t: 0, hipX: s.x, hipY: s.y, lean: 0, barDX: b.dx, barDY: b.dy),
                    BearKey(t: 0.4, hipX: 45, hipY: 86, lean: 16, barDX: b.dx, barDY: b.dy),
                    BearKey(t: 0.5, hipX: 45, hipY: 86, lean: 16, barDX: b.dx, barDY: b.dy),
                    BearKey(t: 0.9, hipX: s.x, hipY: s.y, lean: 0, barDX: b.dx, barDY: b.dy)]
        case .deadlift:
            let h = hang
            return [BearKey(t: 0, hipX: s.x, hipY: s.y, lean: 0, barDX: h.dx, barDY: h.dy),
                    BearKey(t: 0.45, hipX: 42, hipY: 79, lean: 64, barDX: h.dx, barDY: h.dy),
                    BearKey(t: 0.55, hipX: 42, hipY: 79, lean: 64, barDX: h.dx, barDY: h.dy),
                    BearKey(t: 0.95, hipX: s.x, hipY: s.y, lean: 0, barDX: h.dx, barDY: h.dy)]
        case .hangPowerClean:
            let h = hang, r = frontRack
            return [BearKey(t: 0, hipX: 52, hipY: 67, lean: 20, barDX: h.dx, barDY: h.dy),
                    BearKey(t: 0.16, hipX: 50, hipY: 70, lean: 24, barDX: h.dx, barDY: h.dy),
                    BearKey(t: 0.3, hipX: 57, hipY: 63, lean: -6, heel: 6, shrug: 3, barDX: 3, barDY: 20),
                    BearKey(t: 0.38, hipX: 56, hipY: 63.5, lean: -2, heel: 4, shrug: 2, barDX: 9, barDY: 6, elbow: -1),
                    BearKey(t: 0.46, hipX: 52, hipY: 73, lean: 10, barDX: r.dx, barDY: r.dy),
                    BearKey(t: 0.66, hipX: s.x, hipY: s.y, lean: 0, barDX: r.dx, barDY: r.dy),
                    BearKey(t: 0.86, hipX: 52, hipY: 67, lean: 20, barDX: h.dx, barDY: h.dy)]
        case .pushPress:
            let r = frontRack, o = overhead
            return [BearKey(t: 0, hipX: s.x, hipY: s.y, lean: 0, barDX: r.dx, barDY: r.dy),
                    BearKey(t: 0.18, hipX: 53, hipY: 73, lean: 0, barDX: r.dx, barDY: r.dy),
                    BearKey(t: 0.3, hipX: s.x, hipY: 63, lean: -3, heel: 5, barDX: 4, barDY: -17),
                    BearKey(t: 0.42, hipX: s.x, hipY: s.y, lean: 0, barDX: o.dx, barDY: o.dy),
                    BearKey(t: 0.68, hipX: s.x, hipY: s.y, lean: 0, barDX: o.dx, barDY: o.dy),
                    BearKey(t: 0.9, hipX: s.x, hipY: s.y, lean: 0, barDX: r.dx, barDY: r.dy)]
        case .pushJerk:
            let r = frontRack, o = overhead
            return [BearKey(t: 0, hipX: s.x, hipY: s.y, lean: 0, barDX: r.dx, barDY: r.dy),
                    BearKey(t: 0.16, hipX: 53, hipY: 73, lean: 0, barDX: r.dx, barDY: r.dy),
                    BearKey(t: 0.26, hipX: s.x, hipY: 62.5, lean: -3, heel: 6, barDX: 4, barDY: -13),
                    BearKey(t: 0.36, hipX: 51, hipY: 76, lean: 3, barDX: o.dx, barDY: o.dy),
                    BearKey(t: 0.52, hipX: s.x, hipY: s.y, lean: 0, barDX: o.dx, barDY: o.dy),
                    BearKey(t: 0.7, hipX: s.x, hipY: s.y, lean: 0, barDX: o.dx, barDY: o.dy),
                    BearKey(t: 0.9, hipX: s.x, hipY: s.y, lean: 0, barDX: r.dx, barDY: r.dy)]
        }
    }

    /// Interpolated key at loop phase t (smoothstep between keys, wrapping
    /// back to the first key).
    static func key(for lift: Lift, t: Double) -> BearKey {
        let ks = keys(for: lift)
        let tt = t - floor(t)
        var a = ks[ks.count - 1], b = ks[0]
        var span = 1 - a.t, u = (tt - a.t) / max(span, 0.0001)
        for i in 0..<ks.count {
            let next = i + 1 < ks.count ? ks[i + 1] : ks[0]
            let end = i + 1 < ks.count ? next.t : 1
            if tt >= ks[i].t && tt < end {
                a = ks[i]; b = next; span = end - ks[i].t
                u = (tt - ks[i].t) / max(span, 0.0001)
                break
            }
        }
        let e = CGFloat(u * u * (3 - 2 * u))
        func m(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * e }
        return BearKey(t: tt, hipX: m(a.hipX, b.hipX), hipY: m(a.hipY, b.hipY), lean: m(a.lean, b.lean), heel: m(a.heel, b.heel),
                       shrug: m(a.shrug, b.shrug), barDX: m(a.barDX, b.barDX), barDY: m(a.barDY, b.barDY), elbow: m(a.elbow, b.elbow))
    }

    static func pose(for lift: Lift, t: Double) -> BearPose {
        let k = key(for: lift, t: t)
        let ankle = CGPoint(x: groundAnkle.x, y: groundAnkle.y - k.heel)
        let toe = CGPoint(x: groundAnkle.x + 9, y: 106)
        let hip = CGPoint(x: k.hipX, y: k.hipY - k.heel * 0.6)
        let knee = solve(from: ankle, to: hip, a: shin, b: thigh, side: 1)
        let rad = k.lean * .pi / 180
        let len = torso + k.shrug
        let shoulder = CGPoint(x: hip.x + sin(rad) * len, y: hip.y - cos(rad) * len)
        let head = CGPoint(x: shoulder.x + sin(rad * 0.6) * 14 + 5, y: shoulder.y - cos(rad * 0.6) * 14 - 2)
        let bar = CGPoint(x: shoulder.x + k.barDX, y: shoulder.y + k.barDY)
        let elbow = solve(from: shoulder, to: bar, a: upperArm, b: forearm, side: k.elbow)
        return BearPose(ankle: ankle, toe: toe, knee: knee, hip: hip, shoulder: shoulder, head: head, lean: k.lean,
                        elbow: elbow, hand: bar, bar: bar)
    }

    /// Two-bone IK: the joint between `from` and `to` given bone lengths.
    /// `side` picks which way it bends (and scales the bend smoothly).
    static func solve(from p: CGPoint, to q: CGPoint, a: CGFloat, b: CGFloat, side: CGFloat) -> CGPoint {
        let dx = q.x - p.x, dy = q.y - p.y
        let raw = max(sqrt(dx * dx + dy * dy), 0.001)
        let d = min(max(raw, abs(a - b) + 0.01), a + b - 0.01)
        let along = (a * a - b * b + d * d) / (2 * d)
        let h = sqrt(max(a * a - along * along, 0))
        let ux = dx / raw, uy = dy / raw
        let base = CGPoint(x: p.x + ux * along, y: p.y + uy * along)
        // Perpendicular offset: for an upward leg (ankle -> hip) side +1 bends the knee forward.
        return CGPoint(x: base.x - uy * h * side, y: base.y + ux * h * side)
    }
}

/// Debug gallery (UI-testing only): every lift at several phases.
struct BearGallery: View {
    let phases: [Double] = [0, 0.18, 0.3, 0.42, 0.62]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Lift.allCases, id: \.self) { lift in
                    Text(lift.displayName).hand(18)
                    HStack(spacing: 0) {
                        ForEach(phases, id: \.self) { t in
                            BearView(lift: lift, size: 76, frozenAt: t)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 50)
        }
        .background(Palette.paper)
    }
}
