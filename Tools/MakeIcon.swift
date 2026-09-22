import AppKit
import Foundation

// Renders the app icon at every size macOS wants, then leaves an .iconset
// directory for `iconutil` to turn into AppIcon.icns.

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

/// Draws a glyph centred on a point, measured rather than guessed so the two
/// letterforms sit on the same optical grid at every size.
func drawGlyph(_ text: String, size: CGFloat, at centre: NSPoint, color fill: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: .semibold),
        .foregroundColor: fill,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let bounds = string.size()
    string.draw(at: NSPoint(x: centre.x - bounds.width / 2, y: centre.y - bounds.height / 2))
}

func drawIcon(side S: CGFloat) {
    // Rounded-square plate, inset so the icon breathes like other macOS icons.
    let inset = S * 0.09
    let plate = NSRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    let platePath = NSBezierPath(roundedRect: plate,
                                 xRadius: plate.width * 0.2237,
                                 yRadius: plate.width * 0.2237)
    NSGradient(colors: [color(0x4C6EF5), color(0x2B3EAF)])?.draw(in: platePath, angle: -90)

    // Diagonal seam: the two halves of a translation, source above, target below.
    platePath.setClip()
    let seam = NSBezierPath()
    seam.move(to: NSPoint(x: S * 0.14, y: S * 0.14))
    seam.line(to: NSPoint(x: S * 0.86, y: S * 0.86))
    seam.lineWidth = S * 0.022
    color(0xFFFFFF, alpha: 0.22).setStroke()
    seam.stroke()

    // Latin above the seam, CJK below — the shorthand every translator app uses.
    drawGlyph("A", size: S * 0.40, at: NSPoint(x: S * 0.355, y: S * 0.635), color: color(0xFFFFFF))
    drawGlyph("文", size: S * 0.36, at: NSPoint(x: S * 0.645, y: S * 0.360),
              color: color(0xFFFFFF, alpha: 0.92))
}

func writePNG(side: Int, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon(side: CGFloat(side))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    writePNG(side: base, to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(side: base * 2, to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("wrote iconset to \(out.path)")
