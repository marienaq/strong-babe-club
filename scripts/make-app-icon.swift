// Draws the Strong Babe Club app icon: Kettle the kettlebell (dark grey body,
// white face, pink cheeks) on a bubblegum-pink background.
//
// Usage: swift scripts/make-app-icon.swift [output.png]
// Writes a 1024×1024 opaque PNG (iOS masks the corners itself).
import AppKit
import CoreGraphics

let size = 1024
let out = CommandLine.arguments.dropFirst().first
    ?? "App/StrongBabeClub/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let pinkBG = rgb(0xFF9EC0)
let kbGrey = rgb(0x3A3640)
let white = rgb(0xFFFFFF)
let cheek = rgb(0xFF7FA8)

guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("no context") }

// Flip so y grows downward, like the SVG mockups.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

// Background.
ctx.setFillColor(pinkBG)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Soft shadow under the bell, so it sits on the "page" like a sticker.
ctx.setFillColor(rgb(0xD9648F, 0.35))
ctx.fillEllipse(in: CGRect(x: 292, y: 860, width: 440, height: 70))

// Handle.
ctx.setStrokeColor(kbGrey)
ctx.setLineWidth(62)
ctx.setLineCap(.round)
let handle = CGMutablePath()
handle.move(to: CGPoint(x: 352, y: 480))
handle.addCurve(to: CGPoint(x: 672, y: 480), control1: CGPoint(x: 322, y: 110), control2: CGPoint(x: 702, y: 110))
ctx.addPath(handle)
ctx.strokePath()

// Body.
ctx.setFillColor(kbGrey)
ctx.fillEllipse(in: CGRect(x: 512 - 275, y: 365, width: 550, height: 550))

// Subtle shine.
ctx.saveGState()
ctx.translateBy(x: 390, y: 500)
ctx.rotate(by: -0.45)
ctx.setFillColor(rgb(0xFFFFFF, 0.13))
ctx.fillEllipse(in: CGRect(x: -95, y: -42, width: 190, height: 84))
ctx.restoreGState()

// Cheeks.
ctx.setFillColor(cheek)
ctx.fillEllipse(in: CGRect(x: 318, y: 668, width: 92, height: 72))
ctx.fillEllipse(in: CGRect(x: 614, y: 668, width: 92, height: 72))

// Eyes.
ctx.setFillColor(white)
ctx.fillEllipse(in: CGRect(x: 404, y: 590, width: 62, height: 62))
ctx.fillEllipse(in: CGRect(x: 558, y: 590, width: 62, height: 62))

// Smile.
ctx.setStrokeColor(white)
ctx.setLineWidth(26)
ctx.setLineCap(.round)
let smile = CGMutablePath()
smile.move(to: CGPoint(x: 452, y: 712))
smile.addQuadCurve(to: CGPoint(x: 572, y: 712), control: CGPoint(x: 512, y: 772))
ctx.addPath(smile)
ctx.strokePath()

guard let image = ctx.makeImage(),
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
let url = URL(fileURLWithPath: out)
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: url)
print("Wrote \(out)")
