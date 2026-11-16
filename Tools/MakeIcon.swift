// Draws the app icon at every size macOS wants. Usage: makeicon <output.iconset>
import Cocoa

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * s, y: y * s, width: w * s, height: h * s) }

    // Rounded tile with a blue gradient.
    let tile = NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.55, blue: 1.0, alpha: 1),
               ending: NSColor(srgbRed: 0.10, green: 0.25, blue: 0.75, alpha: 1))?.draw(in: tile, angle: -90)

    // Viewfinder corners.
    NSColor.white.setStroke()
    let corners = NSBezierPath()
    corners.lineWidth = 46 * s
    corners.lineCapStyle = .round
    corners.lineJoinStyle = .round
    let (a, b, l): (CGFloat, CGFloat, CGFloat) = (250, 774, 140)
    for (x, y, dx, dy) in [(a, a, 1.0, 1.0), (b, a, -1.0, 1.0), (a, b, 1.0, -1.0), (b, b, -1.0, -1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        corners.move(to: CGPoint(x: x * s, y: (y + dy * l) * s))
        corners.line(to: CGPoint(x: x * s, y: y * s))
        corners.line(to: CGPoint(x: (x + dx * l) * s, y: y * s))
    }
    corners.stroke()

    // Red step badge with a "1".
    let badge = NSBezierPath(ovalIn: r(352, 352, 320, 320))
    let sh = NSShadow(); sh.shadowBlurRadius = 24 * s; sh.shadowOffset = NSSize(width: 0, height: -8 * s)
    sh.shadowColor = NSColor.black.withAlphaComponent(0.35)
    NSGraphicsContext.saveGraphicsState(); sh.set()
    NSColor(srgbRed: 0.92, green: 0.20, blue: 0.17, alpha: 1).setFill(); badge.fill()
    NSGraphicsContext.restoreGraphicsState()
    badge.lineWidth = 22 * s; NSColor.white.setStroke(); badge.stroke()
    let one = NSAttributedString(string: "1", attributes: [
        .font: NSFont.systemFont(ofSize: 230 * s, weight: .heavy), .foregroundColor: NSColor.white,
    ])
    let sz = one.size()
    one.draw(at: CGPoint(x: 512 * s - sz.width / 2, y: 512 * s - sz.height / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for base in [16, 32, 128, 256, 512] {
    for mult in [1, 2] {
        let name = mult == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try? draw(base * mult)?.write(to: out.appendingPathComponent(name))
    }
}
