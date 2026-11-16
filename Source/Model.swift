import Cocoa
import CoreImage

/// Tools shown in the editor toolbar. `key` is the single-letter shortcut.
enum Tool: Int, CaseIterable {
    case select, step, arrow, rect, ellipse, highlight, blur, text, crop

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .step: return "1.circle.fill"
        case .arrow: return "arrow.up.right"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .highlight: return "highlighter"
        case .blur: return "square.grid.3x3.fill"
        case .text: return "textformat"
        case .crop: return "crop"
        }
    }

    var title: String {
        switch self {
        case .select: return "Select"
        case .step: return "Step number"
        case .arrow: return "Arrow"
        case .rect: return "Box"
        case .ellipse: return "Circle"
        case .highlight: return "Highlight"
        case .blur: return "Blur"
        case .text: return "Text"
        case .crop: return "Crop"
        }
    }

    var key: String {
        switch self {
        case .select: return "v"
        case .step: return "s"
        case .arrow: return "a"
        case .rect: return "r"
        case .ellipse: return "o"
        case .highlight: return "h"
        case .blur: return "b"
        case .text: return "t"
        case .crop: return "c"
        }
    }

    var hint: String {
        switch self {
        case .select: return "Click to select, drag to move, drag the dots to reshape. Delete removes. Double-click text to edit."
        case .step: return "Click to drop the next number. Drag from the spot to a target to add a pointer. Type 1–9 to restart numbering."
        case .arrow: return "Drag from the tail to the point. Hold Shift for straight lines."
        case .rect: return "Drag to draw a box. Hold Shift for a square."
        case .ellipse: return "Drag to draw a circle. Hold Shift for a perfect circle."
        case .highlight: return "Drag over the area to highlight."
        case .blur: return "Drag over anything private to pixelate it."
        case .text: return "Click to type. Return finishes, Option-Return adds a line, Esc cancels."
        case .crop: return "Drag the area to keep. Undo puts it back."
        }
    }

    var kind: Kind? {
        switch self {
        case .step: return .step
        case .arrow: return .arrow
        case .rect: return .rect
        case .ellipse: return .ellipse
        case .highlight: return .highlight
        case .blur: return .blur
        case .text: return .text
        case .select, .crop: return nil
        }
    }
}

enum Kind { case step, arrow, rect, ellipse, highlight, blur, text }

struct Annotation {
    var kind: Kind
    var a: CGPoint
    var b: CGPoint
    var color: NSColor
    var size: CGFloat
    var number = 0
    var text = ""
    var hasTail = false

    var rect: CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    mutating func offset(_ dx: CGFloat, _ dy: CGFloat) {
        a.x += dx; a.y += dy; b.x += dx; b.y += dy
    }
}

/// Everything undo needs: the (possibly cropped) image and the annotations on it.
struct DocState {
    var image: CGImage
    var annotations: [Annotation]
}

let palette: [(String, NSColor)] = [
    ("Red", NSColor(srgbRed: 0.90, green: 0.18, blue: 0.16, alpha: 1)),
    ("Orange", NSColor(srgbRed: 0.98, green: 0.55, blue: 0.10, alpha: 1)),
    ("Yellow", NSColor(srgbRed: 1.00, green: 0.84, blue: 0.04, alpha: 1)),
    ("Green", NSColor(srgbRed: 0.16, green: 0.68, blue: 0.30, alpha: 1)),
    ("Blue", NSColor(srgbRed: 0.10, green: 0.45, blue: 0.95, alpha: 1)),
    ("Purple", NSColor(srgbRed: 0.55, green: 0.27, blue: 0.85, alpha: 1)),
    ("Black", NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1)),
    ("White", NSColor.white),
]

// MARK: - Drawing

/// All drawing goes through the current NSGraphicsContext, which is flipped (y grows downward)
/// both on screen and when exporting, so the same code renders both.
enum Renderer {
    static func badgeRadius(_ size: CGFloat) -> CGFloat { 9 + size * 2.2 }
    static func textFont(_ size: CGFloat) -> NSFont { .systemFont(ofSize: 12 + size * 2, weight: .bold) }
    static let textPad: CGFloat = 6

    static func isLight(_ c: NSColor) -> Bool {
        guard let s = c.usingColorSpace(.sRGB) else { return false }
        return 0.299 * s.redComponent + 0.587 * s.greenComponent + 0.114 * s.blueComponent > 0.7
    }

    static func shadow(_ blur: CGFloat = 3) {
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.35)
        sh.shadowBlurRadius = blur
        sh.shadowOffset = NSSize(width: 0, height: -1)
        sh.set()
    }

    static func drawImage(_ img: CGImage, in r: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: r.minX, y: r.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(origin: .zero, size: r.size))
        ctx.restoreGState()
    }

    static func draw(_ an: Annotation, pixelated: CGImage?, canvas: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        switch an.kind {
        case .step: step(an)
        case .arrow: arrow(from: an.a, to: an.b, width: an.size, color: an.color)
        case .rect:
            shadow()
            let p = NSBezierPath(roundedRect: an.rect, xRadius: 3, yRadius: 3)
            p.lineWidth = an.size
            an.color.setStroke(); p.stroke()
        case .ellipse:
            shadow()
            let p = NSBezierPath(ovalIn: an.rect)
            p.lineWidth = an.size
            an.color.setStroke(); p.stroke()
        case .highlight:
            NSGraphicsContext.current?.compositingOperation = .multiply
            an.color.withAlphaComponent(0.45).setFill()
            NSBezierPath(rect: an.rect).fill()
        case .blur:
            guard let pix = pixelated else { return }
            NSBezierPath(rect: an.rect).addClip()
            drawImage(pix, in: canvas)
        case .text: text(an)
        }
    }

    static func arrow(from p: CGPoint, to q: CGPoint, width w: CGFloat, color: NSColor) {
        let dx = q.x - p.x, dy = q.y - p.y
        let len = hypot(dx, dy)
        guard len > 1 else { return }
        let ux = dx / len, uy = dy / len
        let head = min(max(w * 3.6, 12), len * 0.7)
        let half = head * 0.55
        let base = CGPoint(x: q.x - ux * head, y: q.y - uy * head)
        let shaftEnd = CGPoint(x: base.x + ux * min(w, head * 0.3), y: base.y + uy * min(w, head * 0.3))

        let shaft = NSBezierPath()
        shaft.move(to: p); shaft.line(to: shaftEnd)
        shaft.lineCapStyle = .round

        let tri = NSBezierPath()
        tri.move(to: q)
        tri.line(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
        tri.line(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
        tri.close()
        tri.lineJoinStyle = .round

        // A thin outline in a contrasting color keeps arrows visible on any background.
        let outline = isLight(color) ? NSColor.black.withAlphaComponent(0.6) : NSColor.white
        NSGraphicsContext.saveGraphicsState()
        shadow()
        outline.setStroke()
        shaft.lineWidth = w + 3; shaft.stroke()
        tri.lineWidth = 3; tri.stroke()
        NSGraphicsContext.restoreGraphicsState()

        color.setStroke(); color.setFill()
        shaft.lineWidth = w; shaft.stroke()
        tri.fill()
    }

    static func step(_ an: Annotation) {
        let r = badgeRadius(an.size)
        if an.hasTail {
            arrow(from: an.a, to: an.b, width: max(2.5, an.size * 0.8), color: an.color)
        }
        let circle = NSBezierPath(ovalIn: CGRect(x: an.a.x - r, y: an.a.y - r, width: r * 2, height: r * 2))
        NSGraphicsContext.saveGraphicsState()
        shadow(4)
        an.color.setFill(); circle.fill()
        NSGraphicsContext.restoreGraphicsState()
        circle.lineWidth = max(2, r * 0.13)
        (isLight(an.color) ? NSColor.black.withAlphaComponent(0.55) : NSColor.white).setStroke()
        circle.stroke()

        let label = "\(an.number)"
        let fontSize = label.count > 1 ? r * 0.95 : r * 1.15
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: isLight(an.color) ? NSColor.black : NSColor.white,
        ]
        let s = NSAttributedString(string: label, attributes: attrs)
        let sz = s.size()
        s.draw(at: CGPoint(x: an.a.x - sz.width / 2, y: an.a.y - sz.height / 2))
    }

    static func textAttributes(_ an: Annotation) -> [NSAttributedString.Key: Any] {
        [.font: textFont(an.size), .foregroundColor: an.color]
    }

    static func textBacking(_ c: NSColor) -> NSColor {
        isLight(c) ? NSColor(white: 0.1, alpha: 0.88) : NSColor(white: 1, alpha: 0.93)
    }

    static func textRect(_ an: Annotation) -> CGRect {
        let s = NSAttributedString(string: an.text, attributes: textAttributes(an))
        let sz = s.boundingRect(with: CGSize(width: 4000, height: 4000), options: [.usesLineFragmentOrigin]).size
        return CGRect(x: an.a.x, y: an.a.y, width: ceil(sz.width) + textPad * 2, height: ceil(sz.height) + textPad * 2)
    }

    static func text(_ an: Annotation) {
        let r = textRect(an)
        let box = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        shadow(4)
        textBacking(an.color).setFill(); box.fill()
        NSGraphicsContext.restoreGraphicsState()
        an.color.withAlphaComponent(0.8).setStroke()
        box.lineWidth = 1.5; box.stroke()
        NSAttributedString(string: an.text, attributes: textAttributes(an))
            .draw(with: r.insetBy(dx: textPad, dy: textPad), options: [.usesLineFragmentOrigin])
    }

    /// Area an annotation covers, used for selection outlines.
    static func bounds(_ an: Annotation) -> CGRect {
        switch an.kind {
        case .step:
            let r = badgeRadius(an.size)
            var b = CGRect(x: an.a.x - r, y: an.a.y - r, width: r * 2, height: r * 2)
            if an.hasTail { b = b.union(CGRect(origin: an.b, size: .zero)) }
            return b
        case .arrow:
            return an.rect.insetBy(dx: -an.size, dy: -an.size)
        case .text:
            return textRect(an)
        default:
            return an.rect
        }
    }

    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    static func hit(_ an: Annotation, _ p: CGPoint) -> Bool {
        switch an.kind {
        case .step:
            return hypot(p.x - an.a.x, p.y - an.a.y) <= badgeRadius(an.size) + 3
                || (an.hasTail && distance(p, toSegment: an.a, an.b) <= max(7, an.size))
        case .arrow:
            return distance(p, toSegment: an.a, an.b) <= max(8, an.size + 3)
        case .rect, .ellipse:
            // Edges only, so things drawn inside a box stay clickable.
            let r = an.rect
            let slop = max(7, an.size + 3)
            return r.insetBy(dx: -slop, dy: -slop).contains(p)
                && (!r.insetBy(dx: slop, dy: slop).contains(p) || r.width < slop * 3 || r.height < slop * 3)
        case .highlight, .blur:
            return an.rect.insetBy(dx: -4, dy: -4).contains(p)
        case .text:
            return textRect(an).contains(p)
        }
    }

    /// One pixelated copy of the whole image; blur boxes show a clipped window of it.
    static func pixelate(_ img: CGImage, blockPixels: CGFloat) -> CGImage? {
        let ci = CIImage(cgImage: img)
        guard let f = CIFilter(name: "CIPixellate") else { return nil }
        f.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
        f.setValue(blockPixels, forKey: kCIInputScaleKey)
        f.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        guard let out = f.outputImage?.cropped(to: ci.extent) else { return nil }
        return CIContext(options: nil).createCGImage(out, from: ci.extent)
    }
}
