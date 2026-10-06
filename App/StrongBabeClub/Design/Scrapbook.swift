import SwiftUI
import WorkoutCore

// MARK: - Paper

/// Dotted journal paper with the pink margin line.
struct PaperBackground: View {
    var showMargin = true

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.paper))
            let spacing: CGFloat = 18
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)), with: .color(Palette.dot))
                    x += spacing
                }
                y += spacing
            }
            if showMargin {
                ctx.fill(Path(CGRect(x: 30, y: 0, width: 2, height: size.height)), with: .color(Palette.margin))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Ruled lines, like the streak / set-log cards.
struct RuledLines: View {
    var spacing: CGFloat = 22

    var body: some View {
        Canvas { ctx, size in
            var y = spacing - 1
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Palette.ruled))
                y += spacing
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Washi tape

struct WashiTape: View {
    var color: Color
    var stripe: Color
    var width: CGFloat = 60
    var height: CGFloat = 18
    var angle: Double = -4
    var reverse = false

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var p = Path()
                if reverse {
                    p.move(to: CGPoint(x: x, y: size.height))
                    p.addLine(to: CGPoint(x: x + 6, y: size.height))
                    p.addLine(to: CGPoint(x: x + 6 + size.height, y: 0))
                    p.addLine(to: CGPoint(x: x + size.height, y: 0))
                } else {
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x + 6, y: 0))
                    p.addLine(to: CGPoint(x: x + 6 + size.height, y: size.height))
                    p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                }
                ctx.fill(p, with: .color(stripe))
                x += 12
            }
        }
        .frame(width: width, height: height)
        .opacity(0.85)
        .rotationEffect(.degrees(angle))
        .accessibilityHidden(true)
    }

    static func forKind(_ kind: SectionKind, width: CGFloat = 60, angle: Double = -4) -> WashiTape {
        WashiTape(color: kind.color, stripe: kind.lightColor, width: width, angle: angle, reverse: angle > 0)
    }
}

// MARK: - Cards

/// A white "taped-in" card, slightly rotated.
struct PaperCard<Content: View>: View {
    var rotation: Double = 0
    var tape: WashiTape?
    var tapeAlignment: Alignment = .top
    var ruled: CGFloat?
    var padding = EdgeInsets(top: 16, leading: 14, bottom: 12, trailing: 14)
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    Palette.card
                    if let ruled { RuledLines(spacing: ruled) }
                }
            }
            .shadow(color: Palette.ink.opacity(0.08), radius: 4, y: 3)
            .overlay(alignment: tapeAlignment) {
                if let tape { tape.offset(y: -9) }
            }
            .rotationEffect(.degrees(rotation))
    }
}

/// Ticket-edged pink note for Kettle's message.
struct ZigzagBottom: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.12))
        let teeth = 11
        for i in 0...teeth {
            let x = r.maxX - r.width * CGFloat(i) / CGFloat(teeth)
            let y = i % 2 == 0 ? r.maxY - r.height * 0.1 : r.maxY
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        return p
    }
}

/// Wobbly hand-drawn square used as the list bullet.
struct DoodleSquare: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 22
        var p = Path()
        p.move(to: CGPoint(x: 3 * s, y: 4 * s))
        p.addCurve(to: CGPoint(x: 19 * s, y: 3 * s), control1: CGPoint(x: 8 * s, y: 3 * s), control2: CGPoint(x: 14 * s, y: 4 * s))
        p.addCurve(to: CGPoint(x: 20 * s, y: 19 * s), control1: CGPoint(x: 20 * s, y: 8 * s), control2: CGPoint(x: 19 * s, y: 14 * s))
        p.addCurve(to: CGPoint(x: 4 * s, y: 20 * s), control1: CGPoint(x: 15 * s, y: 20 * s), control2: CGPoint(x: 9 * s, y: 19 * s))
        p.addCurve(to: CGPoint(x: 3 * s, y: 4 * s), control1: CGPoint(x: 3 * s, y: 15 * s), control2: CGPoint(x: 4 * s, y: 9 * s))
        p.closeSubpath()
        return p
    }
}

// MARK: - Doodles

/// The orange squiggle under headings.
struct Squiggle: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 160, sy = r.height / 12
        var p = Path()
        p.move(to: CGPoint(x: 2 * sx, y: 8 * sy))
        p.addCurve(to: CGPoint(x: 78 * sx, y: 6 * sy), control1: CGPoint(x: 28 * sx, y: 2 * sy), control2: CGPoint(x: 50 * sx, y: 11 * sy))
        p.addCurve(to: CGPoint(x: 158 * sx, y: 7 * sy), control1: CGPoint(x: 106 * sx, y: 1 * sy), control2: CGPoint(x: 132 * sx, y: 2 * sy))
        return p
    }
}

/// Hand-drawn loop around a number.
struct HandCircle: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 70, sy = r.height / 66
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
        var p = Path()
        p.move(to: pt(38, 5))
        p.addCurve(to: pt(5, 36), control1: pt(14, 2), control2: pt(3, 20))
        p.addCurve(to: pt(43, 59), control1: pt(7, 52), control2: pt(25, 62))
        p.addCurve(to: pt(64, 25), control1: pt(61, 56), control2: pt(67, 39))
        p.addCurve(to: pt(30, 7), control1: pt(61, 11), control2: pt(48, 4))
        return p
    }
}

/// Curvy arrow next to "you've got this!".
struct DoodleArrow: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 34
        var p = Path()
        p.move(to: CGPoint(x: 6 * s, y: 4 * s))
        p.addCurve(to: CGPoint(x: 26 * s, y: 26 * s), control1: CGPoint(x: 16 * s, y: 6 * s), control2: CGPoint(x: 24 * s, y: 14 * s))
        p.move(to: CGPoint(x: 20 * s, y: 22 * s))
        p.addLine(to: CGPoint(x: 26 * s, y: 27 * s))
        p.addLine(to: CGPoint(x: 30 * s, y: 20 * s))
        return p
    }
}

/// Doodle that draws itself in (stroke trim). Static under Reduce Motion.
struct DrawnStroke<S: Shape>: View {
    var shape: S
    var color: Color
    var lineWidth: CGFloat
    var delay: Double = 0.2
    var duration: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        shape.trim(from: 0, to: reduceMotion ? 1 : progress)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: duration).delay(delay)) { progress = 1 }
            }
            .accessibilityHidden(true)
    }
}

/// Yellow highlighter swipe behind a number.
struct Highlighter: View {
    var delay: Double = 1.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 6, bottomTrailingRadius: 14, topTrailingRadius: 12)
            .fill(Palette.sunny.opacity(0.75))
            .scaleEffect(x: reduceMotion || shown ? 1 : 0, y: 1, anchor: .leading)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.6).delay(delay)) { shown = true }
            }
            .accessibilityHidden(true)
    }
}
