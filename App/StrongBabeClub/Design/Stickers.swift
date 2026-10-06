import SwiftUI
import WorkoutCore

// Die-cut sticker artwork, redrawn from the mockup SVGs.

struct BarbellIcon: View {
    var plate: Color = Palette.cream
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 54, sy = size.height / 28
            ctx.fill(Path(roundedRect: CGRect(x: 2 * sx, y: 12 * sy, width: 50 * sx, height: 4 * sy), cornerRadius: 2 * sy), with: .color(Palette.ink))
            for x in [9.0, 38.0] {
                ctx.fill(Path(roundedRect: CGRect(x: x * sx, y: 3 * sy, width: 7 * sx, height: 22 * sy), cornerRadius: 3.5 * sx), with: .color(plate))
            }
        }
        .aspectRatio(54 / 28, contentMode: .fit)
    }
}

struct DumbbellIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: .degrees(-35))
            ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
            ctx.fill(Path(roundedRect: CGRect(x: 4 * s, y: 11 * s, width: 16 * s, height: 2.4 * s), cornerRadius: 1.2 * s), with: .color(Palette.ink))
            for x in [3.0, 17.0] {
                ctx.fill(Path(roundedRect: CGRect(x: x * s, y: 7.5 * s, width: 4 * s, height: 9 * s), cornerRadius: 1.6 * s), with: .color(Palette.cream))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct StarShape: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 24
        let pts: [(CGFloat, CGFloat)] = [(12, 2.5), (14.8, 8.5), (21.3, 9.1), (16.4, 13.5), (17.9, 19.9), (12, 16.6), (6.1, 19.9), (7.6, 13.5), (2.7, 9.1), (9.2, 8.5)]
        var p = Path()
        p.move(to: CGPoint(x: pts[0].0 * s + r.minX, y: pts[0].1 * s + r.minY))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0 * s + r.minX, y: q.1 * s + r.minY)) }
        p.closeSubpath()
        return p
    }
}

struct StarIcon: View {
    var body: some View {
        ZStack {
            StarShape().fill(Palette.cream)
            StarShape().stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct FlameIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 24, sy = size.height / 28
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
            var outer = Path()
            outer.move(to: pt(12, 1))
            outer.addCurve(to: pt(19, 15), control1: pt(13.5, 6), control2: pt(19, 8.5))
            outer.addArc(center: pt(12, 15), radius: 7 * sx, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            outer.addCurve(to: pt(7.5, 5.5), control1: pt(5, 11), control2: pt(7.5, 9.5))
            outer.addCurve(to: pt(11.5, 12.5), control1: pt(10, 7), control2: pt(11.5, 9.5))
            ctx.fill(outer, with: .color(Palette.tangerine))
            ctx.stroke(outer, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
            var inner = Path()
            inner.move(to: pt(12, 25))
            inner.addCurve(to: pt(8.5, 21.5), control1: pt(10, 25), control2: pt(8.5, 23.5))
            inner.addCurve(to: pt(12, 15.5), control1: pt(8.5, 19.5), control2: pt(10.5, 18.5))
            inner.addCurve(to: pt(15.5, 21.5), control1: pt(13.5, 18.5), control2: pt(15.5, 19.5))
            inner.addCurve(to: pt(12, 25), control1: pt(15.5, 23.5), control2: pt(14, 25))
            ctx.fill(inner, with: .color(Palette.sunny))
        }
        .aspectRatio(24 / 28, contentMode: .fit)
    }
}

/// Kettle, the kettlebell mascot.
struct KettleFace: View {
    var body: some View {
        Canvas { ctx, size in
        let s = size.width / 56
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var handle = Path()
        handle.move(to: pt(17, 22))
        handle.addCurve(to: pt(39, 22), control1: pt(17, 7), control2: pt(39, 7))
        ctx.stroke(handle, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 5 * s, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: 9 * s, y: 18 * s, width: 38 * s, height: 38 * s)), with: .color(Palette.cream))
        for x in [22.0, 34.0] {
            ctx.fill(Path(ellipseIn: CGRect(x: (x - 2.8) * s, y: 33.2 * s, width: 5.6 * s, height: 5.6 * s)), with: .color(Palette.ink))
        }
        var smile = Path()
        smile.move(to: pt(24, 42))
        smile.addQuadCurve(to: pt(32, 42), control: pt(28, 47))
        ctx.stroke(smile, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
        for x in [18.0, 38.0] {
            ctx.fill(Path(ellipseIn: CGRect(x: (x - 2.6) * s, y: 39.4 * s, width: 5.2 * s, height: 5.2 * s)), with: .color(Palette.bubblegum))
        }
        }
        .aspectRatio(56 / 58, contentMode: .fit)
    }
}

struct BearFaceIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 40
            func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s))
            }
            let style = StrokeStyle(lineWidth: 2.5 * s)
            for (x, y, r) in [(11.0, 11.0, 5.0), (29.0, 11.0, 5.0), (20.0, 22.0, 13.0)] {
                ctx.fill(circle(x, y, r), with: .color(Palette.cream))
                ctx.stroke(circle(x, y, r), with: .color(Palette.ink), style: style)
            }
            ctx.fill(circle(15, 20, 1.8), with: .color(Palette.ink))
            ctx.fill(circle(25, 20, 1.8), with: .color(Palette.ink))
            let snout = Path(ellipseIn: CGRect(x: 15.5 * s, y: 23.8 * s, width: 9 * s, height: 6.4 * s))
            ctx.fill(snout, with: .color(Palette.cream))
            ctx.stroke(snout, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2 * s))
            ctx.fill(circle(20, 26, 1.4), with: .color(Palette.ink))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

extension StickerID {
    var background: Color {
        switch self {
        case .barbell: return Palette.tangerine
        case .kettle: return Palette.bubblegum
        case .dumbbell: return Palette.sky
        case .bear: return Palette.mint
        case .flame: return Palette.sunnyPale
        case .star: return Palette.sunny
        case .rainbow: return Palette.skyPale
        case .crown: return Palette.sunny
        case .trophy: return Palette.mintPale
        case .rocket: return Palette.pinkPaper
        case .diamond: return Palette.skyLight
        }
    }

    /// "Squat bear" follows the chosen animal ("Squat fox").
    var displayName: String {
        if self == .bear {
            let animal = AppDefaults.store.string(forKey: Animal.storageKey).flatMap(Animal.init(rawValue:)) ?? .bear
            return "Squat \(animal.rawValue)"
        }
        return StickerCatalog.definition(self).name
    }

    /// Shape on the sticker page, as in the mockup.
    var cornerRadius: CGFloat {
        switch self {
        case .dumbbell: return 12
        default: return 20
        }
    }
}

/// One die-cut sticker: colored disc, white border, artwork, drop shadow.
struct StickerView: View {
    var id: StickerID
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: id == .star ? size / 4 : min(id.cornerRadius, size / 2))
            .fill(id.background)
            .overlay {
                RoundedRectangle(cornerRadius: id == .star ? size / 4 : min(id.cornerRadius, size / 2))
                    .strokeBorder(.white, lineWidth: max(2.5, size * 0.075))
            }
            .overlay { art.frame(width: size * 0.6, height: size * 0.6) }
            .frame(width: size, height: size)
            .stickerShadow()
            .accessibilityElement()
            .accessibilityLabel("\(id.displayName) sticker")
    }

    @ViewBuilder var art: some View {
        switch id {
        case .barbell: BarbellIcon()
        case .kettle: KettleFace()
        case .dumbbell: DumbbellIcon()
        case .bear: BearFaceIcon()
        case .flame: FlameIcon()
        case .star: StarIcon()
        case .rainbow: Image(systemName: "rainbow").resizable().scaledToFit().symbolRenderingMode(.multicolor)
        case .crown: Image(systemName: "crown.fill").resizable().scaledToFit().foregroundStyle(Palette.ink)
        case .trophy: Image(systemName: "trophy.fill").resizable().scaledToFit().foregroundStyle(Palette.mintDeep)
        case .rocket: Image(systemName: "paperplane.fill").resizable().scaledToFit().foregroundStyle(Palette.berry)
        case .diamond: Image(systemName: "suit.diamond.fill").resizable().scaledToFit().foregroundStyle(Palette.skyDeep)
        }
    }
}

/// A square on "my sticker page".
struct StickerSlotView: View {
    var slot: StickerSlot
    var index: Int
    private let rotations: [Double] = [-8, 6, -3, 10, -6, 4, 0, -10, 7, -4, 9, 0]

    var body: some View {
        let rot = rotations[index % rotations.count]
        Group {
            switch slot {
            case .sticker(let id, _):
                StickerView(id: id, size: 40)
            case .empty:
                Circle()
                    .strokeBorder(Palette.dashed, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .frame(width: 40, height: 40)
                    .accessibilityLabel("Empty sticker spot")
            case .today:
                placeholder(Text("today?"), color: Palette.tangerineActive)
                    .pulse()
                    .accessibilityLabel("Today's sticker, not earned yet")
            }
        }
        .slapOn(rotation: rot, delay: 0.5 + 0.07 * Double(index))
    }

    func placeholder(_ text: Text, color: Color) -> some View {
        Circle().fill(Palette.cream)
            .overlay(Circle().strokeBorder(Color(hex: 0xE3D3C2), lineWidth: 3))
            .overlay(text.font(Typeface.hand(14)).foregroundStyle(color).multilineTextAlignment(.center).lineSpacing(-4))
            .frame(width: 40, height: 40)
            .accessibilityElement()
    }
}
