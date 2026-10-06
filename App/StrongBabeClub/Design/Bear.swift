import SwiftUI
import WorkoutCore

/// The line-art bear that acts out the day's lift. One animation per lift,
/// all driven by a single 2.6 s loop; frozen in the start pose under
/// Reduce Motion.
struct BearView: View {
    var lift: Lift
    var size: CGFloat = 112
    var fill: Color = Palette.paper
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                BearCanvas(lift: lift, t: 0, fill: fill)
            } else {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6) / 2.6
                    BearCanvas(lift: lift, t: t, fill: fill)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Line-art bear doing \(lift.displayName.lowercased())s")
    }
}

/// Pose parameters for one frame (in the mockup's 120×120 coordinate space).
struct BearPose: Equatable {
    /// Body offset (down = squat depth).
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    /// Knee position.
    var knee = CGPoint(x: 60, y: 88)
    /// Hip position (top of thigh).
    var hip = CGPoint(x: 58, y: 68)
    /// Torso lean in degrees (hinge).
    var lean: Double = 0
    /// Barbell plate center, in body coordinates.
    var bar = CGPoint(x: 70, y: 40)

    /// Keyframes: 0 -> 0.4 down, hold to 0.5, back up by 0.9.
    static func ease(_ t: Double) -> CGFloat {
        let u: Double
        switch t {
        case ..<0.4: u = t / 0.4
        case ..<0.5: u = 1
        case ..<0.9: u = 1 - (t - 0.5) / 0.4
        default: u = 0
        }
        return CGFloat(0.5 - 0.5 * cos(u * .pi))
    }

    static func pose(for lift: Lift, t: Double) -> BearPose {
        let u = ease(t)
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * u }
        var p = BearPose()
        switch lift {
        case .frontSquat, .backSquat:
            p.dx = lerp(0, -6)
            p.dy = lerp(0, 22)
            p.knee = CGPoint(x: lerp(60, 72), y: lerp(88, 92))
            p.hip = CGPoint(x: lerp(58, 52), y: lerp(68, 90))
            p.bar = lift == .frontSquat ? CGPoint(x: 70, y: 40) : CGPoint(x: 52, y: 36)
        case .deadlift:
            // Hinge: torso tips forward, bar travels floor <-> hip.
            p.lean = Double(lerp(0, 55))
            p.dy = lerp(0, 8)
            p.knee = CGPoint(x: lerp(60, 66), y: lerp(88, 90))
            p.hip = CGPoint(x: lerp(58, 54), y: lerp(68, 74))
            p.bar = CGPoint(x: lerp(66, 74), y: lerp(64, 70))
        case .hangPowerClean:
            // Bar from hip to shoulders with a little dip.
            let v = 1 - u
            p.dy = 6 * sin(CGFloat(t) * .pi * 2) * 0.5 + 3
            p.bar = CGPoint(x: 70, y: 40 + 26 * v)
        case .pushPress, .pushJerk:
            // Dip, then drive the bar overhead (jerk dips lower to catch).
            let v = 1 - u
            p.dy = lift == .pushJerk ? 10 * v : 6 * v
            p.knee = CGPoint(x: 60 + 6 * v, y: 88 + 2 * v)
            p.hip = CGPoint(x: 58 - 2 * v, y: 68 + 8 * v)
            p.bar = CGPoint(x: 60, y: 40 - 34 * u)
        }
        return p
    }
}

struct BearCanvas: View {
    var lift: Lift
    var t: Double
    var fill: Color

    var body: some View {
        let pose = BearPose.pose(for: lift, t: t)
        Canvas { ctx, size in
            let s = size.width / 120
            ctx.scaleBy(x: s, y: s)
            let ink = GraphicsContext.Shading.color(Palette.ink)
            let line = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            // Floor
            var floor = Path()
            floor.move(to: CGPoint(x: 30, y: 110))
            floor.addLine(to: CGPoint(x: 96, y: 110))
            ctx.stroke(floor, with: ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 6]))
            // Leg: foot, shin, thigh
            var leg = Path()
            leg.move(to: CGPoint(x: 70, y: 108))
            leg.addLine(to: CGPoint(x: 60, y: 108))
            leg.addLine(to: pose.knee)
            leg.addLine(to: pose.hip)
            ctx.stroke(leg, with: ink, style: line)

            // Upper body (translated for squat depth, rotated for hinge).
            var body = ctx
            body.translateBy(x: pose.dx, y: pose.dy)
            body.translateBy(x: 57, y: 68)
            body.rotate(by: .degrees(pose.lean))
            body.translateBy(x: -57, y: -68)
            func blob(_ r: CGRect, _ w: CGFloat = 3) {
                let p = Path(ellipseIn: r)
                body.fill(p, with: .color(fill))
                body.stroke(p, with: ink, style: StrokeStyle(lineWidth: w))
            }
            blob(CGRect(x: 46, y: 40, width: 22, height: 30))
            blob(CGRect(x: 48.5, y: 12.5, width: 9, height: 9), 2.5)
            blob(CGRect(x: 61.5, y: 12.5, width: 9, height: 9), 2.5)
            blob(CGRect(x: 49, y: 16, width: 22, height: 22))
            blob(CGRect(x: 65, y: 26.4, width: 10, height: 7.2), 2.5)
            body.fill(Path(ellipseIn: CGRect(x: 72.4, y: 27.4, width: 3.2, height: 3.2)), with: ink)
            body.fill(Path(ellipseIn: CGRect(x: 62.4, y: 22.4, width: 3.2, height: 3.2)), with: ink)
            body.fill(Path(ellipseIn: CGRect(x: 59.8, y: 28.8, width: 4.4, height: 4.4)), with: .color(Palette.bubblegum.opacity(0.8)))
            // Arm to the bar
            var arm = Path()
            arm.move(to: CGPoint(x: 60, y: 46))
            arm.addLine(to: CGPoint(x: (60 + pose.bar.x) / 2 + 4, y: (46 + pose.bar.y) / 2 + 4))
            arm.addLine(to: pose.bar)
            body.stroke(arm, with: ink, style: line)
            // Barbell end (orange plate)
            let plate = Path(ellipseIn: CGRect(x: pose.bar.x - 10, y: pose.bar.y - 10, width: 20, height: 20))
            body.fill(plate, with: .color(Palette.tangerine))
            body.stroke(plate, with: ink, style: StrokeStyle(lineWidth: 2.5))
            body.fill(Path(ellipseIn: CGRect(x: pose.bar.x - 2.5, y: pose.bar.y - 2.5, width: 5, height: 5)), with: ink)
        }
    }
}
