import Cocoa
import ImageIO

extension Notification.Name {
    /// Posted whenever a file is added to or removed from the captures folder.
    static let capturesChanged = Notification.Name("MCSCapturesChanged")
}

enum ImageLoader {
    /// Loads full-resolution pixels and the Retina scale (from the file's DPI).
    static func load(_ url: URL) -> (CGImage, CGFloat)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        var scale: CGFloat = 1
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let dpi = props[kCGImagePropertyDPIWidth] as? Double, dpi > 72 {
            scale = CGFloat(dpi / 72)
        }
        return (img, scale)
    }

    static func thumbnail(_ url: URL, maxPixels: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}

/// One capture in the history: the newest version of it, plus the untouched original.
struct CaptureEntry {
    let display: URL     // marked-up copy if there is one, else the original
    let original: URL?
    let date: Date
    let title: String
    var isMarkedUp: Bool { display != original }

    static let markedSuffix = " marked up"

    static func baseName(of url: URL) -> String {
        let n = url.deletingPathExtension().lastPathComponent
        return n.hasSuffix(markedSuffix) ? String(n.dropLast(markedSuffix.count)) : n
    }

    /// Newest first. "X marked up.png" and "X.png" are shown as one entry.
    static func scan(_ folder: URL, limit: Int = 80) -> [CaptureEntry] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let exts: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif"]
        var groups: [String: (marked: URL?, original: URL?, date: Date)] = [:]
        for u in urls where exts.contains(u.pathExtension.lowercased()) {
            let base = baseName(of: u)
            let date = (try? u.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
            var g = groups[base] ?? (nil, nil, .distantPast)
            if u.deletingPathExtension().lastPathComponent.hasSuffix(markedSuffix) { g.marked = u } else { g.original = u }
            g.date = max(g.date, date)
            groups[base] = g
        }
        return groups.compactMap { base, g in
            guard let display = g.marked ?? g.original else { return nil }
            return CaptureEntry(display: display, original: g.original, date: g.date, title: base)
        }
        .sorted { $0.date > $1.date }
        .prefix(limit)
        .map { $0 }
    }
}

private final class ThumbButton: NSButton {
    var entry: CaptureEntry!
    var isCurrent = false { didSet { updateBorder() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        title = ""
        imageScaling = .scaleProportionallyDown
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        widthAnchor.constraint(equalToConstant: 104).isActive = true
        heightAnchor.constraint(equalToConstant: 66).isActive = true
        updateBorder()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateBorder() {
        layer?.borderWidth = isCurrent ? 3 : 1
        layer?.borderColor = (isCurrent ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }
}

/// Snagit-style tray of recent captures along the bottom of the editor.
final class HistoryStrip: NSView {
    var onOpen: ((URL) -> Void)?
    var onOpenNewWindow: ((URL) -> Void)?
    var currentURL: URL? { didSet { markCurrent() } }

    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private let empty = NSTextField(labelWithString: "Your captures will appear here.")
    private var buttons: [ThumbButton] = []
    private static var cache: [String: NSImage] = [:]
    private static let queue = DispatchQueue(label: "mcs.thumbs", qos: .userInitiated)

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let flipped = FlippedView()
        flipped.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(stack)
        scroll.documentView = flipped
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.translatesAutoresizingMaskIntoConstraints = false
        empty.textColor = .secondaryLabelColor
        empty.font = .systemFont(ofSize: 12)
        empty.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        addSubview(empty)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            flipped.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            flipped.bottomAnchor.constraint(equalTo: scroll.contentView.bottomAnchor),
            flipped.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: flipped.centerYAnchor),
            empty.centerXAnchor.constraint(equalTo: centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .capturesChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc func reload() {
        let entries = CaptureEntry.scan(AppDelegate.capturesFolder)
        buttons.forEach { $0.removeFromSuperview() }
        buttons = entries.map { e in
            let b = ThumbButton()
            b.entry = e
            b.target = self
            b.action = #selector(clicked(_:))
            let f = DateFormatter()
            f.dateStyle = .medium; f.timeStyle = .short
            b.toolTip = "\(e.title)\(e.isMarkedUp ? " (marked up)" : "")\n\(f.string(from: e.date))\nClick to open here. Right-click for more."
            b.setAccessibilityLabel(e.title)
            b.menu = contextMenu(for: e)
            stack.addArrangedSubview(b)
            loadThumb(into: b, url: e.display, date: e.date)
            return b
        }
        empty.isHidden = !entries.isEmpty
        markCurrent()
    }

    private func loadThumb(into b: ThumbButton, url: URL, date: Date) {
        let key = "\(url.path)|\(date.timeIntervalSince1970)"
        if let img = HistoryStrip.cache[key] { b.image = img; return }
        HistoryStrip.queue.async {
            let img = ImageLoader.thumbnail(url, maxPixels: 240)
            DispatchQueue.main.async {
                if let img { HistoryStrip.cache[key] = img }
                if b.entry.display == url { b.image = img }
            }
        }
    }

    private func markCurrent() {
        let cur = currentURL.map(CaptureEntry.baseName(of:))
        for b in buttons {
            b.isCurrent = cur != nil && CaptureEntry.baseName(of: b.entry.display) == cur
                && b.entry.display.deletingLastPathComponent() == currentURL?.deletingLastPathComponent()
        }
    }

    @objc private func clicked(_ sender: ThumbButton) { onOpen?(sender.entry.display) }

    // MARK: Right-click menu

    private func contextMenu(for e: CaptureEntry) -> NSMenu {
        let m = NSMenu()
        func add(_ title: String, _ sel: Selector, _ url: URL?) {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            i.representedObject = url
            m.addItem(i)
        }
        add("Open", #selector(menuOpen(_:)), e.display)
        add("Open in New Window", #selector(menuOpenNew(_:)), e.display)
        if e.isMarkedUp, let o = e.original { add("Open Original (without markup)", #selector(menuOpen(_:)), o) }
        m.addItem(.separator())
        add("Copy Image", #selector(menuCopy(_:)), e.display)
        add("Show in Finder", #selector(menuReveal(_:)), e.display)
        m.addItem(.separator())
        let trash = NSMenuItem(title: "Move to Trash", action: #selector(menuTrash(_:)), keyEquivalent: "")
        trash.target = self
        trash.representedObject = [e.display, e.original].compactMap { $0 }.uniqued()
        m.addItem(trash)
        return m
    }

    @objc private func menuOpen(_ s: NSMenuItem) { if let u = s.representedObject as? URL { onOpen?(u) } }
    @objc private func menuOpenNew(_ s: NSMenuItem) { if let u = s.representedObject as? URL { onOpenNewWindow?(u) } }
    @objc private func menuReveal(_ s: NSMenuItem) {
        if let u = s.representedObject as? URL { NSWorkspace.shared.activateFileViewerSelecting([u]) }
    }
    @objc private func menuCopy(_ s: NSMenuItem) {
        guard let u = s.representedObject as? URL, let data = try? Data(contentsOf: u) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        if let tiff = NSBitmapImageRep(data: data)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        pb.writeObjects([item])
    }
    @objc private func menuTrash(_ s: NSMenuItem) {
        guard let urls = s.representedObject as? [URL] else { return }
        // Trash, not delete: it can be put back from the Trash in Finder.
        for u in urls { try? FileManager.default.trashItem(at: u, resultingItemURL: nil) }
        NotificationCenter.default.post(name: .capturesChanged, object: nil)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private extension Array where Element == URL {
    func uniqued() -> [URL] {
        var seen = Set<URL>()
        return filter { seen.insert($0).inserted }
    }
}
