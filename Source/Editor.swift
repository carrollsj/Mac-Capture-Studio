import Cocoa
import UniformTypeIdentifiers

/// Keeps a smaller-than-window image centered instead of pinned to a corner.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return r }
        let f = doc.frame
        if r.width > f.width { r.origin.x = (f.width - r.width) / 2 }
        if r.height > f.height { r.origin.y = (f.height - r.height) / 2 }
        return r
    }
}

final class SwatchButton: NSButton {
    let swatch: NSColor
    var isChosen = false { didSet { needsDisplay = true } }

    init(color: NSColor, name: String) {
        swatch = color
        super.init(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        isBordered = false
        title = ""
        toolTip = name
        setAccessibilityLabel(name)
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 3, dy: 3)
        let dot = NSBezierPath(ovalIn: r)
        swatch.setFill(); dot.fill()
        NSColor.black.withAlphaComponent(0.25).setStroke()
        dot.lineWidth = 1; dot.stroke()
        if isChosen {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75))
            ring.lineWidth = 1.5
            NSColor.controlAccentColor.setStroke(); ring.stroke()
        }
    }
}

/// Drag this into Mail, Slack, Messages or Finder to drop the marked-up PNG.
final class DragWell: NSView, NSDraggingSource {
    var provider: (() -> URL?)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        toolTip = "Drag the marked-up image into Mail, Slack, Messages or a folder"
        setAccessibilityLabel("Drag image")
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 64, height: 24) }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        box.lineWidth = 1
        box.setLineDash([3, 2], count: 2, phase: 0)
        NSColor.secondaryLabelColor.setStroke(); box.stroke()
        let s = NSAttributedString(string: "⇱ Drag", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor,
        ])
        let sz = s.size()
        s.draw(at: CGPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDragged(with e: NSEvent) {
        guard let url = provider?() else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let thumb = NSImage(contentsOf: url) ?? NSImage()
        let maxSide: CGFloat = 160
        let ratio = min(1, maxSide / max(thumb.size.width, thumb.size.height, 1))
        let size = CGSize(width: thumb.size.width * ratio, height: thumb.size.height * ratio)
        let p = convert(e.locationInWindow, from: nil)
        item.setDraggingFrame(CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), contents: thumb)
        beginDraggingSession(with: [item], event: e, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

final class EditorController: NSWindowController, NSWindowDelegate {
    private(set) var canvas: CanvasView
    let scroll = NSScrollView()
    private(set) var baseName: String
    private(set) var sourceURL: URL?
    var onClose: ((EditorController) -> Void)?
    var onOpenNewWindow: ((URL) -> Void)?
    private var saveURL: URL?
    private let history = HistoryStrip()
    private var historyHeight: NSLayoutConstraint!
    private var hoverArea: NSTrackingArea?
    private let toolControl = NSSegmentedControl()
    private var swatches: [SwatchButton] = []
    private let sizeSlider = NSSlider(value: 4, minValue: 1, maxValue: 12, target: nil, action: nil)
    private let stepField = NSTextField(labelWithString: "1")
    private let stepper = NSStepper()
    private let hint = NSTextField(labelWithString: "")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let toast = NSTextField(labelWithString: "")
    private var undoButton: NSButton!
    private var redoButton: NSButton!

    init(image: CGImage, scale: CGFloat, name: String, sourceURL: URL? = nil) {
        canvas = CanvasView(image: image, scale: scale)
        baseName = CaptureEntry.baseName(of: URL(fileURLWithPath: name + ".png"))
        self.sourceURL = sourceURL
        EditorController.applyPreferences(canvas)

        let pts = CanvasView.pointSize(image, scale)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let vis = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let chromeH: CGFloat = 46 + 26 + 84
        let w = min(max(pts.width + 40, 980), vis.width * 0.9)
        let h = min(max(pts.height + chromeH + 40, 520), vis.height * 0.9)
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: w, height: h),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        win.title = name
        win.minSize = NSSize(width: 980, height: 420)
        win.isReleasedWhenClosed = false
        win.setFrameOrigin(CGPoint(x: vis.midX - w / 2, y: vis.midY - h / 2))
        super.init(window: win)
        win.delegate = self
        adoptSource(sourceURL)
        buildUI()
        canvas.onChange = { [weak self] in self?.refresh(); self?.scheduleLiveCopy() }
        refresh()
    }

    private static func applyPreferences(_ c: CanvasView) {
        let d = UserDefaults.standard
        if d.object(forKey: "tool") != nil, let t = Tool(rawValue: d.integer(forKey: "tool")), t != .crop { c.tool = t }
        if d.object(forKey: "colorIndex") != nil { c.color = palette[min(max(d.integer(forKey: "colorIndex"), 0), palette.count - 1)].1 }
        if d.object(forKey: "size") != nil { c.size = CGFloat(d.double(forKey: "size")) }
    }

    /// Reopening a "marked up" file saves back over it instead of making "marked up marked up".
    private func adoptSource(_ url: URL?) {
        sourceURL = url
        if let url, url.deletingPathExtension().lastPathComponent.hasSuffix(CaptureEntry.markedSuffix) {
            saveURL = url
        } else {
            saveURL = nil
        }
        if let url { baseName = CaptureEntry.baseName(of: url) }
        window?.title = baseName
        window?.representedURL = url
        history.currentURL = url
    }

    /// Swap a different capture into this window (from the history strip), keeping unsaved markup.
    func load(_ url: URL) {
        guard url != sourceURL else { return }
        guard let (img, scale) = ImageLoader.load(url) else { NSSound.beep(); return }
        canvas.commitText()
        if canvas.dirty { write(to: saveURL ?? defaultSaveURL) }
        let tool = canvas.tool, color = canvas.color, size = canvas.size
        let c = CanvasView(image: img, scale: scale)
        c.tool = tool == .crop ? .select : tool
        c.color = color
        c.size = size
        c.onChange = { [weak self] in self?.refresh(); self?.scheduleLiveCopy() }
        canvas = c
        scroll.documentView = c
        adoptSource(url)
        zoomToFit(nil)
        window?.makeFirstResponder(c)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: UI

    private func symbolButton(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip.components(separatedBy: "\n").first) ?? NSImage(), target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.toolTip = tip
        return b
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        toolControl.segmentCount = Tool.allCases.count
        toolControl.trackingMode = .selectOne
        toolControl.segmentStyle = .texturedRounded
        for t in Tool.allCases {
            toolControl.setImage(NSImage(systemSymbolName: t.symbol, accessibilityDescription: t.title), forSegment: t.rawValue)
            toolControl.setToolTip(t.help, forSegment: t.rawValue)
            toolControl.setWidth(34, forSegment: t.rawValue)
        }
        toolControl.target = self
        toolControl.action = #selector(toolChanged)

        let colorRow = NSStackView()
        colorRow.spacing = 1
        for (i, (name, c)) in palette.enumerated() {
            let s = SwatchButton(color: c, name: name)
            s.tag = i; s.target = self; s.action = #selector(colorChosen(_:))
            s.toolTip = "\(name)\nColor for new items. Also recolors the selected item."
            swatches.append(s); colorRow.addArrangedSubview(s)
        }

        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        sizeSlider.isContinuous = true
        sizeSlider.doubleValue = Double(canvas.size)
        sizeSlider.widthAnchor.constraint(equalToConstant: 80).isActive = true
        sizeSlider.toolTip = "Size\nHow thick lines are and how big numbers and text are. Changes the selected item too."
        let sizeLabel = NSTextField(labelWithString: "Size")
        sizeLabel.textColor = .secondaryLabelColor

        let stepLabel = NSTextField(labelWithString: "Next")
        stepLabel.textColor = .secondaryLabelColor
        stepField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        stepField.alignment = .center
        stepField.widthAnchor.constraint(equalToConstant: 22).isActive = true
        stepper.minValue = 1; stepper.maxValue = 99; stepper.increment = 1; stepper.valueWraps = false
        stepper.target = self; stepper.action = #selector(stepperChanged)
        stepper.toolTip = "Next step number\nThe number the next step will get. If that number is already used, the new step is inserted and later steps move up."

        undoButton = symbolButton("arrow.uturn.backward", "Undo  (⌘Z)\nTakes back the last change, including crops.", #selector(undoClicked))
        redoButton = symbolButton("arrow.uturn.forward", "Redo  (⇧⌘Z)\nPuts back what you just undid.", #selector(redoClicked))
        let copy = NSButton(title: "Copy", target: self, action: #selector(copy(_:)))
        copy.bezelStyle = .rounded
        copy.keyEquivalent = ""
        copy.toolTip = "Copy  (⌘C)\nCopies the marked-up image so you can paste it into an email, chat or doc. ⌘Return copies and closes."
        copy.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copy.imagePosition = .imageLeading
        let save = NSButton(title: "Save", target: self, action: #selector(saveDocument(_:)))
        save.bezelStyle = .rounded
        save.toolTip = "Save  (⌘S)\nSaves the marked-up image to Pictures › Mac Capture Studio. ⇧⌘S lets you choose where."
        let well = DragWell()
        well.provider = { [weak self] in self?.dragFile() }

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        for v in [toolControl, colorRow, sizeLabel, sizeSlider, stepLabel, stepField, stepper] as [NSView] { bar.addView(v, in: .leading) }
        bar.setCustomSpacing(18, after: toolControl)
        bar.setCustomSpacing(18, after: colorRow)
        bar.setCustomSpacing(18, after: sizeSlider)
        bar.setCustomSpacing(2, after: stepField)
        for v in [undoButton!, redoButton!, well, save, copy] as [NSView] { bar.addView(v, in: .trailing) }
        bar.setCustomSpacing(16, after: redoButton)

        let barBackground = NSVisualEffectView()
        barBackground.material = .titlebar
        barBackground.blendingMode = .withinWindow

        let clip = CenteringClipView()
        scroll.contentView = clip
        scroll.documentView = canvas
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.1
        scroll.maxMagnification = 6
        scroll.backgroundColor = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua]) != nil ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.84, alpha: 1) }
        scroll.drawsBackground = true
        NotificationCenter.default.addObserver(self, selector: #selector(zoomed), name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)

        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        hint.lineBreakMode = .byTruncatingTail
        zoomLabel.textColor = .secondaryLabelColor
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.alignment = .right

        toast.font = .systemFont(ofSize: 13, weight: .semibold)
        toast.textColor = .white
        toast.backgroundColor = NSColor.black.withAlphaComponent(0.78)
        toast.drawsBackground = true
        toast.alignment = .center
        toast.isHidden = true
        toast.wantsLayer = true
        toast.layer?.cornerRadius = 8
        toast.layer?.masksToBounds = true

        let divider = NSBox(); divider.boxType = .separator
        let divider2 = NSBox(); divider2.boxType = .separator
        history.onOpen = { [weak self] url in self?.load(url) }
        history.onOpenNewWindow = { [weak self] url in self?.onOpenNewWindow?(url) }
        history.currentURL = sourceURL
        history.reload()
        let divider3 = NSBox(); divider3.boxType = .separator
        historyHeight = history.heightAnchor.constraint(equalToConstant: UserDefaults.standard.bool(forKey: "hideHistory") ? 0 : 84)
        for v in [barBackground, bar, divider, scroll, divider3, history, divider2, hint, zoomLabel, toast] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            barBackground.topAnchor.constraint(equalTo: content.topAnchor),
            barBackground.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            barBackground.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            barBackground.heightAnchor.constraint(equalToConstant: 46),
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 46),
            divider.topAnchor.constraint(equalTo: bar.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            divider3.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            divider3.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            divider3.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            history.topAnchor.constraint(equalTo: divider3.bottomAnchor),
            history.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            history.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            historyHeight,
            divider2.topAnchor.constraint(equalTo: history.bottomAnchor),
            divider2.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            divider2.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            hint.topAnchor.constraint(equalTo: divider2.bottomAnchor, constant: 5),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -6),
            zoomLabel.centerYAnchor.constraint(equalTo: hint.centerYAnchor),
            zoomLabel.leadingAnchor.constraint(greaterThanOrEqualTo: hint.trailingAnchor, constant: 12),
            zoomLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            toast.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -18),
            toast.heightAnchor.constraint(equalToConstant: 30),
        ])
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Hovering any toolbar control shows its description in the bottom bar right away.
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        bar.addTrackingArea(area)
        hoverArea = area
        toolbarView = bar
    }

    private weak var toolbarView: NSView?
    private var hovering: String?

    override func mouseMoved(with event: NSEvent) { updateHover(event) }
    override func mouseEntered(with event: NSEvent) { updateHover(event) }
    override func mouseExited(with event: NSEvent) { hovering = nil; refresh() }

    private func updateHover(_ event: NSEvent) {
        guard let bar = toolbarView, let content = window?.contentView else { return }
        let p = content.convert(event.locationInWindow, from: nil)
        var view = content.hitTest(p)
        var text: String?
        while let v = view, v !== bar {
            if v === toolControl {
                let x = toolControl.convert(event.locationInWindow, from: nil).x
                var edge: CGFloat = 0
                for t in Tool.allCases {
                    edge += toolControl.width(forSegment: t.rawValue) + 1
                    if x < edge { text = t.help; break }
                }
                break
            }
            if let tip = v.toolTip, !tip.isEmpty { text = tip; break }
            view = v.superview
        }
        hovering = text?.replacingOccurrences(of: "\n", with: " — ")
        refresh()
    }

    func showAndFit() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.layoutIfNeeded()
        zoomToFit(nil)
        window?.makeFirstResponder(canvas)
    }

    private func refresh() {
        toolControl.selectedSegment = canvas.tool.rawValue
        hint.stringValue = hovering ?? canvas.tool.hint
        hint.textColor = hovering == nil ? .secondaryLabelColor : .labelColor
        stepField.stringValue = "\(canvas.nextStep)"
        stepper.integerValue = canvas.nextStep
        undoButton?.isEnabled = canvas.canUndo
        redoButton?.isEnabled = canvas.canRedo
        for s in swatches { s.isChosen = s.swatch == canvas.color }
        zoomLabel.stringValue = "\(Int((scroll.magnification * 100).rounded()))%"
        window?.isDocumentEdited = canvas.dirty
    }

    @objc private func toolChanged() {
        canvas.tool = Tool(rawValue: toolControl.selectedSegment) ?? .select
        UserDefaults.standard.set(canvas.tool.rawValue, forKey: "tool")
        window?.makeFirstResponder(canvas)
    }

    @objc private func colorChosen(_ sender: SwatchButton) {
        canvas.applyColor(sender.swatch)
        UserDefaults.standard.set(sender.tag, forKey: "colorIndex")
        refresh()
        window?.makeFirstResponder(canvas)
    }

    @objc private func sizeChanged() {
        let done = NSApp.currentEvent?.type == .leftMouseUp
        canvas.applySize(CGFloat(sizeSlider.doubleValue.rounded()), final: done)
        UserDefaults.standard.set(sizeSlider.doubleValue.rounded(), forKey: "size")
        if done { window?.makeFirstResponder(canvas) }
    }

    @objc private func stepperChanged() {
        canvas.nextStep = stepper.integerValue
        canvas.tool = .step
        window?.makeFirstResponder(canvas)
    }

    @objc private func undoClicked() { canvas.undo(nil) }
    @objc private func redoClicked() { canvas.redo(nil) }

    @objc private func zoomed() { refresh() }

    // MARK: Zoom

    private func setZoom(_ z: CGFloat) {
        let center = CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
        scroll.setMagnification(min(max(z, scroll.minMagnification), scroll.maxMagnification), centeredAt: center)
        refresh()
    }

    @objc func zoomIn(_ sender: Any?) { setZoom(scroll.magnification * 1.25) }
    @objc func zoomOut(_ sender: Any?) { setZoom(scroll.magnification / 1.25) }
    @objc func zoomActual(_ sender: Any?) { setZoom(1) }
    @objc func zoomToFit(_ sender: Any?) {
        let avail = scroll.contentSize
        let size = canvas.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        setZoom(min(1, (avail.width - 24) / size.width, (avail.height - 24) / size.height))
    }

    // MARK: Output

    private func flash(_ text: String) {
        toast.stringValue = "   \(text)   "
        toast.isHidden = false
        toast.alphaValue = 1
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideToast), object: nil)
        perform(#selector(hideToast), with: nil, afterDelay: 1.8)
    }

    /// Brief message over the image, e.g. "Copied to clipboard" right after a capture.
    func announce(_ text: String) { flash(text) }

    static var liveClipboard: Bool { UserDefaults.standard.bool(forKey: "liveClipboard") }

    private func scheduleLiveCopy() {
        guard EditorController.liveClipboard, canvas.dirty else { return }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(liveCopy), object: nil)
        perform(#selector(liveCopy), with: nil, afterDelay: 0.4)
    }

    /// Keeps the clipboard matching the markup, without counting as "saved".
    @objc private func liveCopy() {
        guard let png = canvas.renderedPNG(commitEditing: false) else { return }
        EditorController.putOnClipboard(png)
    }

    static func putOnClipboard(_ png: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        pb.writeObjects([item])
    }

    @objc private func hideToast() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            toast.animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.toast.isHidden = true })
    }

    @discardableResult
    private func copyToClipboard() -> Bool {
        guard let png = canvas.renderedPNG() else { NSSound.beep(); return false }
        EditorController.putOnClipboard(png)
        canvas.dirty = false
        refresh()
        return true
    }

    @objc func copy(_ sender: Any?) {
        if copyToClipboard() { flash("Copied. Paste it into an email, chat or doc.") }
    }

    @objc func copyAndClose(_ sender: Any?) {
        if copyToClipboard() { window?.close() }
    }

    private var defaultSaveURL: URL {
        AppDelegate.capturesFolder.appendingPathComponent("\(baseName) marked up.png")
    }

    @discardableResult
    private func write(to url: URL) -> Bool {
        guard let png = canvas.renderedPNG() else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            saveURL = url
            NotificationCenter.default.post(name: .capturesChanged, object: nil)
            canvas.dirty = false
            refresh()
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        let url = saveURL ?? defaultSaveURL
        if write(to: url) { flash("Saved to \(url.deletingLastPathComponent().lastPathComponent) as “\(url.lastPathComponent)”") }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard let win = window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (saveURL ?? defaultSaveURL).lastPathComponent
        panel.directoryURL = (saveURL ?? defaultSaveURL).deletingLastPathComponent()
        panel.beginSheetModal(for: win) { [weak self] r in
            guard r == .OK, let url = panel.url, let self else { return }
            if self.write(to: url) { self.flash("Saved “\(url.lastPathComponent)”") }
        }
    }

    @objc func showInFinder(_ sender: Any?) {
        let url = saveURL ?? defaultSaveURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(AppDelegate.capturesFolder)
        }
    }

    private func dragFile() -> URL? {
        guard let png = canvas.renderedPNG() else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MacCaptureStudioDrag", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(baseName).png")
        do { try png.write(to: url) } catch { return nil }
        canvas.dirty = false
        refresh()
        return url
    }

    @objc func toggleHistory(_ sender: Any?) {
        let hide = historyHeight.constant > 0
        UserDefaults.standard.set(hide, forKey: "hideHistory")
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            historyHeight.animator().constant = hide ? 0 : 84
        }
    }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleHistory(_:)) {
            item.title = historyHeight.constant > 0 ? "Hide Capture History" : "Show Capture History"
        }
        return true
    }

    // MARK: Window

    func windowDidBecomeKey(_ notification: Notification) { history.reload() }

    func windowWillClose(_ notification: Notification) {
        canvas.commitText()
        // Never lose work: unsaved markup is kept next to the original capture.
        if canvas.dirty { write(to: saveURL ?? defaultSaveURL) }
        onClose?(self)
    }
}
