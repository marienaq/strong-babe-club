import SwiftUI
import WorkoutCore

/// The mascot that acts out the lifts. Every animal shares one pose rig
/// (`BearPose` keyframes per lift) and adds its own skin: colours, ears,
/// snout, tail and markings. 12 animals × 6 lifts with no per-animal animation.
enum Animal: String, CaseIterable, Identifiable, Sendable {
    case bear, bunny, cat, dog, fox, frog, koala, otter, panda, penguin, pig, sloth

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    static let storageKey = "animal"

    var skin: AnimalSkin {
        switch self {
        case .bear: return AnimalSkin(fur: Palette.paper, ears: .round, snout: .bear, tail: .nub)
        case .bunny: return AnimalSkin(fur: Color(hex: 0xFDF7F9), inner: Palette.bubblegumLight, ears: .long, snout: .button, tail: .puff, whiskers: true)
        case .cat: return AnimalSkin(fur: Color(hex: 0xE9E3EE), inner: Palette.bubblegumLight, ears: .pointy, snout: .button, tail: .long, whiskers: true)
        case .dog: return AnimalSkin(fur: Color(hex: 0xF3DDB8), ears: .floppy, earColor: Color(hex: 0xC99A66), snout: .dog, tail: .wag)
        case .fox: return AnimalSkin(fur: Color(hex: 0xFFB27A), belly: Palette.cream, inner: Palette.cream, ears: .pointy, snout: .pointy, tail: .bushy)
        case .frog: return AnimalSkin(fur: Color(hex: 0xA6E3A1), belly: Color(hex: 0xE6F7D9), ears: .frogEyes, snout: .smile, tail: .none)
        case .koala: return AnimalSkin(fur: Color(hex: 0xD3D3DA), inner: Palette.bubblegumLight, ears: .fluffy, snout: .bigNose, tail: .nub)
        case .otter: return AnimalSkin(fur: Color(hex: 0xC9A27E), belly: Color(hex: 0xF1E1CC), ears: .tiny, snout: .muzzle, tail: .flat, whiskers: true)
        case .panda: return AnimalSkin(fur: .white, limbs: Color(hex: 0x3B3345), ears: .round, earColor: Color(hex: 0x3B3345), snout: .bear, tail: .nub, eyePatches: true)
        case .penguin: return AnimalSkin(fur: Color(hex: 0x4A4458), belly: .white, limbs: Color(hex: 0x4A4458), ears: .none, snout: .beak, tail: .none, faceMask: .white)
        case .pig: return AnimalSkin(fur: Color(hex: 0xFFD0DD), inner: Palette.bubblegum, ears: .tiny, snout: .pig, tail: .curly)
        case .sloth: return AnimalSkin(fur: Color(hex: 0xC8B49A), ears: .none, snout: .button, tail: .none, faceMask: Color(hex: 0xF1E6D6), eyeStripes: true)
        }
    }
}

struct AnimalSkin {
    enum Ears { case round, long, pointy, floppy, fluffy, tiny, frogEyes, none }
    enum Snout { case bear, button, dog, pointy, smile, bigNose, muzzle, beak, pig }
    enum Tail { case nub, puff, long, wag, bushy, flat, curly, none }

    var fur: Color
    var belly: Color? = nil
    var limbs: Color? = nil
    var inner: Color? = nil
    var ears: Ears
    var earColor: Color? = nil
    var snout: Snout
    var tail: Tail
    var whiskers = false
    var eyePatches = false
    var faceMask: Color? = nil
    var eyeStripes = false
}

/// Draws one frame: the shared rig posed by `pose`, dressed in `skin`.
struct LifterCanvas: View {
    var pose: BearPose
    var skin: AnimalSkin
    /// Override for the bear's fill (cards use white).
    var paperOverride: Color?

    var body: some View {
        let p = pose
        let s = skin
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / 120, y: size.height / 120)
            let ink = GraphicsContext.Shading.color(Palette.ink)
            let fur = GraphicsContext.Shading.color(paperOverride ?? s.fur)
            let limbFill = GraphicsContext.Shading.color(s.limbs ?? paperOverride ?? s.fur)
            func line(_ pts: [CGPoint]) -> Path {
                var path = Path()
                path.move(to: pts[0])
                pts.dropFirst().forEach { path.addLine(to: $0) }
                return path
            }
            func round(_ w: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
            func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
            }
            func blob(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, fill f: GraphicsContext.Shading, line w: CGFloat = 3) {
                ctx.fill(ellipse(c, rx, ry), with: f)
                ctx.stroke(ellipse(c, rx, ry), with: ink, lineWidth: w)
            }
            func dot(_ c: CGPoint, _ r: CGFloat, _ color: GraphicsContext.Shading = .color(Palette.ink)) {
                ctx.fill(ellipse(c, r, r), with: color)
            }
            func poly(_ pts: [CGPoint], fill f: GraphicsContext.Shading, w: CGFloat = 2.5) {
                var path = line(pts)
                path.closeSubpath()
                ctx.fill(path, with: f)
                ctx.stroke(path, with: ink, style: round(w))
            }

            // Floor
            var floor = Path()
            floor.move(to: CGPoint(x: 26, y: 109))
            floor.addLine(to: CGPoint(x: 98, y: 109))
            ctx.stroke(floor, with: ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [1, 6]))

            let rad = p.lean * .pi / 180
            let back = CGPoint(x: p.hip.x - 10 * cos(rad) - 1, y: p.hip.y - 1 - 10 * sin(rad) * 0.3)

            // Tail (behind the body)
            switch s.tail {
            case .bushy:
                let tip = CGPoint(x: back.x - 9, y: back.y + 2)
                blob(CGPoint(x: back.x - 5, y: back.y + 1), 8, 5, fill: fur, line: 2.5)
                blob(tip, 3.4, 3, fill: .color(Palette.cream), line: 2)
            case .long:
                var tail = Path()
                tail.move(to: back)
                tail.addCurve(to: CGPoint(x: back.x - 12, y: back.y - 14), control1: CGPoint(x: back.x - 10, y: back.y + 4),
                              control2: CGPoint(x: back.x - 16, y: back.y - 6))
                ctx.stroke(tail, with: ink, style: round(6.5))
                ctx.stroke(tail, with: fur, style: round(3))
            case .flat:
                blob(CGPoint(x: back.x - 6, y: back.y + 4), 8, 3, fill: fur, line: 2.5)
            case .wag:
                var tail = Path()
                tail.move(to: back)
                tail.addQuadCurve(to: CGPoint(x: back.x - 7, y: back.y - 10), control: CGPoint(x: back.x - 9, y: back.y))
                ctx.stroke(tail, with: ink, style: round(6))
                ctx.stroke(tail, with: fur, style: round(2.8))
            case .curly:
                var tail = Path()
                tail.addArc(center: CGPoint(x: back.x - 3, y: back.y - 2), radius: 3, startAngle: .degrees(0), endAngle: .degrees(300), clockwise: false)
                ctx.stroke(tail, with: ink, style: round(2.5))
            case .puff: blob(back, 5, 5, fill: .color(.white), line: 2.5)
            case .nub: blob(back, 3.2, 3.2, fill: fur, line: 2.5)
            case .none: break
            }

            // Body + chunky legs: ink outline pass, then fill pass, so joints merge.
            let leg = line([p.hip, p.knee, p.ankle])
            let foot = line([p.ankle, p.toe])
            let trunk = line([p.hip, p.shoulder])
            ctx.stroke(trunk, with: ink, style: round(27))
            ctx.stroke(leg, with: ink, style: round(20))
            ctx.stroke(foot, with: ink, style: round(12))
            ctx.stroke(trunk, with: fur, style: round(22))
            ctx.stroke(leg, with: limbFill, style: round(15))
            ctx.stroke(foot, with: s.snout == .beak ? .color(Palette.tangerine) : limbFill, style: round(7))
            // Belly
            let mid = CGPoint(x: (p.hip.x + p.shoulder.x) / 2 + 5 * cos(rad), y: (p.hip.y + p.shoulder.y) / 2 + 5 * sin(rad))
            if let belly = s.belly {
                ctx.fill(ellipse(mid, 5.5, 8.5), with: .color(belly))
            } else {
                ctx.fill(ellipse(mid, 4, 6), with: .color(Palette.bubblegum.opacity(0.35)))
            }

            func drawPlate() {
                let plate = ellipse(p.bar, 8.5, 8.5)
                ctx.fill(plate, with: .color(Palette.tangerine))
                ctx.stroke(plate, with: ink, lineWidth: 2.5)
                dot(p.bar, 2.5)
            }
            func drawArm() {
                let arm = line([p.shoulder, p.elbow, p.hand])
                ctx.stroke(arm, with: ink, style: round(11))
                ctx.stroke(arm, with: limbFill, style: round(6.5))
            }
            func drawHead() {
                let h = p.head
                let earFill = GraphicsContext.Shading.color(s.earColor ?? paperOverride ?? s.fur)
                let innerFill = GraphicsContext.Shading.color(s.inner ?? Palette.bubblegumLight)
                // Ears behind the head
                switch s.ears {
                case .round:
                    blob(CGPoint(x: h.x - 5, y: h.y - 10), 4.6, 4.6, fill: earFill, line: 2.5)
                    blob(CGPoint(x: h.x + 6, y: h.y - 10), 4.6, 4.6, fill: earFill, line: 2.5)
                case .long:
                    for (x, tilt) in [(h.x - 4.0, -0.25), (h.x + 4.5, 0.15)] {
                        var e = ctx
                        e.translateBy(x: x, y: h.y - 17)
                        e.rotate(by: .radians(tilt))
                        let outer = ellipse(.zero, 3.6, 10)
                        e.fill(outer, with: earFill)
                        e.stroke(outer, with: ink, lineWidth: 2.5)
                        e.fill(ellipse(CGPoint(x: 0, y: 1), 1.6, 7), with: innerFill)
                    }
                case .pointy:
                    poly([CGPoint(x: h.x - 10, y: h.y - 5), CGPoint(x: h.x - 7, y: h.y - 18), CGPoint(x: h.x - 1, y: h.y - 9)], fill: earFill)
                    poly([CGPoint(x: h.x + 2, y: h.y - 10), CGPoint(x: h.x + 8, y: h.y - 19), CGPoint(x: h.x + 10, y: h.y - 5)], fill: earFill)
                case .floppy:
                    for x in [h.x - 9.5, h.x + 1] {
                        blob(CGPoint(x: x, y: h.y - 2), 3.8, 8, fill: earFill, line: 2.5)
                    }
                case .fluffy:
                    for c in [CGPoint(x: h.x - 9, y: h.y - 8), CGPoint(x: h.x + 7, y: h.y - 10)] {
                        blob(c, 7, 6.5, fill: earFill, line: 2.5)
                        dot(c, 3.5, innerFill)
                    }
                case .tiny:
                    poly([CGPoint(x: h.x - 8, y: h.y - 7), CGPoint(x: h.x - 6, y: h.y - 14), CGPoint(x: h.x - 1, y: h.y - 10)], fill: earFill)
                    poly([CGPoint(x: h.x + 3, y: h.y - 10), CGPoint(x: h.x + 8, y: h.y - 15), CGPoint(x: h.x + 9, y: h.y - 7)], fill: earFill)
                case .frogEyes, .none:
                    break
                }
                // Head
                blob(h, 11, 11, fill: fur)
                if let mask = s.faceMask { ctx.fill(ellipse(CGPoint(x: h.x + 3, y: h.y + 1.5), 8, 7.5), with: .color(mask)) }
                if s.eyePatches { ctx.fill(ellipse(CGPoint(x: h.x + 3.8, y: h.y - 2.6), 3.6, 3), with: .color(Color(hex: 0x3B3345))) }
                if s.eyeStripes {
                    var stripe = Path()
                    stripe.move(to: CGPoint(x: h.x - 2, y: h.y - 4))
                    stripe.addLine(to: CGPoint(x: h.x + 8, y: h.y - 1))
                    ctx.stroke(stripe, with: .color(Color(hex: 0x7A6650)), style: round(3.4))
                }
                // Eye
                if s.ears == .frogEyes {
                    for c in [CGPoint(x: h.x - 1, y: h.y - 10), CGPoint(x: h.x + 7, y: h.y - 10)] {
                        blob(c, 4.4, 4.4, fill: fur, line: 2.5)
                        dot(CGPoint(x: c.x + 1, y: c.y), 1.7)
                    }
                } else {
                    dot(CGPoint(x: h.x + 4, y: h.y - 3), 1.6, s.eyePatches ? .color(.white) : .color(Palette.ink))
                }
                // Snout / nose / mouth
                switch s.snout {
                case .bear:
                    blob(CGPoint(x: h.x + 10, y: h.y + 3), 5, 3.6, fill: fur, line: 2.5)
                    dot(CGPoint(x: h.x + 14, y: h.y + 2), 1.6)
                case .dog:
                    blob(CGPoint(x: h.x + 10, y: h.y + 3.5), 5.5, 4, fill: .color(Palette.cream), line: 2.5)
                    dot(CGPoint(x: h.x + 14.5, y: h.y + 2), 2.2)
                case .button:
                    poly([CGPoint(x: h.x + 9, y: h.y + 1), CGPoint(x: h.x + 12, y: h.y + 1), CGPoint(x: h.x + 10.5, y: h.y + 3.2)],
                         fill: .color(Palette.bubblegum), w: 1.5)
                case .pointy:
                    poly([CGPoint(x: h.x + 5, y: h.y - 1), CGPoint(x: h.x + 17, y: h.y + 3.5), CGPoint(x: h.x + 5, y: h.y + 8)],
                         fill: .color(Palette.cream))
                    dot(CGPoint(x: h.x + 16.5, y: h.y + 3.5), 1.8)
                case .smile:
                    var mouth = Path()
                    mouth.move(to: CGPoint(x: h.x + 1, y: h.y + 4))
                    mouth.addQuadCurve(to: CGPoint(x: h.x + 10, y: h.y + 3), control: CGPoint(x: h.x + 6, y: h.y + 9))
                    ctx.stroke(mouth, with: ink, style: round(2))
                case .bigNose:
                    blob(CGPoint(x: h.x + 9.5, y: h.y + 2), 3.4, 4.6, fill: .color(Color(hex: 0x4A4458)), line: 2)
                case .muzzle:
                    blob(CGPoint(x: h.x + 9.5, y: h.y + 3), 4.6, 3.4, fill: .color(s.belly ?? Palette.cream), line: 2.5)
                    dot(CGPoint(x: h.x + 12.5, y: h.y + 1.8), 1.6)
                case .beak:
                    poly([CGPoint(x: h.x + 8, y: h.y), CGPoint(x: h.x + 16, y: h.y + 2.5), CGPoint(x: h.x + 8, y: h.y + 5)],
                         fill: .color(Palette.sunny), w: 2)
                case .pig:
                    blob(CGPoint(x: h.x + 11, y: h.y + 2), 3.6, 4.4, fill: .color(Palette.bubblegum), line: 2.5)
                    dot(CGPoint(x: h.x + 10.5, y: h.y + 0.5), 0.9)
                    dot(CGPoint(x: h.x + 11.5, y: h.y + 3.5), 0.9)
                }
                if s.whiskers {
                    for dy in [CGFloat(1.5), 4] {
                        var w = Path()
                        w.move(to: CGPoint(x: h.x + 12, y: h.y + dy))
                        w.addLine(to: CGPoint(x: h.x + 19, y: h.y + dy - 1 + dy * 0.3))
                        ctx.stroke(w, with: ink, style: round(1))
                    }
                }
                // Blush
                dot(CGPoint(x: h.x + 2, y: h.y + 4), 2.2, .color(Palette.bubblegum.opacity(0.75)))
            }
            // Bar on the back sits behind the head; otherwise the plate is in front.
            if p.bar.x < p.shoulder.x - 2 && p.bar.y > p.shoulder.y - 12 {
                drawArm(); drawPlate(); drawHead()
            } else {
                drawHead(); drawArm(); drawPlate()
            }
        }
    }
}

/// Contact sheet (test mode): every animal × every lift at a telling moment.
struct AnimalGallery: View {
    /// A characteristic phase per lift (bottom of the squat, lockout, catch...).
    static let phase: [Lift: Double] = [.backSquat: 0.45, .frontSquat: 0.45, .deadlift: 0.5, .hangPowerClean: 0.42,
                                        .pushPress: 0.55, .pushJerk: 0.36]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("").frame(width: 46)
                ForEach(Lift.allCases, id: \.self) { lift in
                    Text(lift.displayName.split(separator: " ").map { String($0.prefix(1)) }.joined())
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                }
            }
            ForEach(Animal.allCases) { animal in
                HStack(spacing: 0) {
                    Text(animal.displayName).font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.ink).frame(width: 46, alignment: .leading)
                    ForEach(Lift.allCases, id: \.self) { lift in
                        BearView(lift: lift, size: 56, frozenAt: Self.phase[lift], animal: animal)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 54)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.paper)
    }
}
