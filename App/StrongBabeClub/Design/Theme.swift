import SwiftUI
import WorkoutCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// "Sherbet" palette from the approved scrapbook mockups.
enum Palette {
    static let paper = Color(hex: 0xFFF8EE)
    static let cream = Color(hex: 0xFFF4E8)
    static let dot = Color(hex: 0xE8D9C8)
    static let margin = Color(hex: 0xFFC4D6)
    static let ink = Color(hex: 0x2B1B3D)
    static let muted = Color(hex: 0x6E5F7E)
    static let faint = Color(hex: 0x9A8FA8)
    static let note = Color(hex: 0x4A3B5A)
    static let card = Color.white
    static let ruled = Color(hex: 0xDCE6FF)
    static let dashed = Color(hex: 0xC9B8A6)
    static let inputLine = Color(hex: 0xD9CCBD)

    static let tangerine = Color(hex: 0xFF6B3D)
    static let tangerineLight = Color(hex: 0xFF8D66)
    static let tangerineDeep = Color(hex: 0xC2410C)
    static let tangerineActive = Color(hex: 0xE5532A)
    static let sunny = Color(hex: 0xFFC94D)
    static let sunnyLight = Color(hex: 0xFFD978)
    static let sunnyPale = Color(hex: 0xFFE7A8)
    static let sunnyDeep = Color(hex: 0x8A5A00)
    static let sky = Color(hex: 0x6E9BFF)
    static let skyLight = Color(hex: 0x9BBBFF)
    static let skyPale = Color(hex: 0xC9D9FF)
    static let skyDeep = Color(hex: 0x2F57C9)
    static let mint = Color(hex: 0x3CC8A5)
    static let mintLight = Color(hex: 0x7EDCC4)
    static let mintPale = Color(hex: 0xBDEEDF)
    static let mintDeep = Color(hex: 0x147A5F)
    static let bubblegum = Color(hex: 0xFF9EC0)
    static let bubblegumLight = Color(hex: 0xFFB8D0)
    static let pinkPaper = Color(hex: 0xFFE3EE)
    static let berry = Color(hex: 0xB3265E)
    static let sheetDim = Color(hex: 0x5A4A66)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

extension SectionKind {
    /// Section colors: sunny warm-up, tangerine strength, sky metabolic, mint cool-down.
    var color: Color {
        switch self {
        case .warmup: return Palette.sunny
        case .strength: return Palette.tangerine
        case .metabolic: return Palette.sky
        case .cooldown: return Palette.mint
        }
    }

    var lightColor: Color {
        switch self {
        case .warmup: return Palette.sunnyLight
        case .strength: return Palette.tangerineLight
        case .metabolic: return Palette.skyLight
        case .cooldown: return Palette.mintLight
        }
    }

    var paleColor: Color {
        switch self {
        case .warmup: return Palette.sunnyPale
        case .strength: return Color(hex: 0xFFE2D6)
        case .metabolic: return Palette.skyPale
        case .cooldown: return Palette.mintPale
        }
    }

    /// Readable label color on paper.
    var deepColor: Color {
        switch self {
        case .warmup: return Palette.sunnyDeep
        case .strength: return Palette.tangerineDeep
        case .metabolic: return Palette.skyDeep
        case .cooldown: return Palette.mintDeep
        }
    }
}

/// Caveat (handwriting labels) and Nunito (body). Both are bundled under the
/// SIL Open Font License; if they fail to load the system rounded font is used.
/// Sizes scale with Dynamic Type via `relativeTo:`.
enum Typeface {
    static func hand(_ size: CGFloat, _ weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .body) -> Font {
        if FontRegistry.isAvailable("Caveat") {
            // Use the variable font's named instances rather than `.weight()`.
            let name = weight == .regular || weight == .medium || weight == .light ? "Caveat-Regular" : "CaveatRoman-Bold"
            return .custom(name, size: size, relativeTo: style)
        }
        return .system(size: size, weight: weight, design: .rounded).italic()
    }

    static func body(_ size: CGFloat, _ weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .body) -> Font {
        if FontRegistry.isAvailable("Nunito") {
            return .custom("Nunito", size: size, relativeTo: style).weight(weight)
        }
        return .system(size: size, weight: weight, design: .rounded)
    }
}

enum FontRegistry {
    private static var cache: [String: Bool] = [:]

    static func isAvailable(_ family: String) -> Bool {
        if let v = cache[family] { return v }
        #if canImport(UIKit)
        let v = !UIFont.fontNames(forFamilyName: family).isEmpty
        #else
        let v = NSFontManager.shared.availableMembers(ofFontFamily: family) != nil
        #endif
        cache[family] = v
        return v
    }
}

extension View {
    /// Handwritten label style.
    func hand(_ size: CGFloat, _ weight: Font.Weight = .bold, color: Color = Palette.ink) -> some View {
        font(Typeface.hand(size, weight)).foregroundStyle(color)
    }

    /// Nunito body style.
    func bodyText(_ size: CGFloat, _ weight: Font.Weight = .bold, color: Color = Palette.ink) -> some View {
        font(Typeface.body(size, weight)).foregroundStyle(color)
    }
}

extension Text {
    /// Caveat's slanted last glyph inks past its advance width and SwiftUI
    /// clips it ("Al|l", "weigh|t"). A little kern after the last character
    /// keeps it whole without spreading the rest of the word.
    static func caveat(_ string: String) -> Text {
        var a = AttributedString(string)
        if let last = a.characters.indices.last {
            a[last..<a.endIndex].kern = 2.5
        }
        return Text(a)
    }
}
