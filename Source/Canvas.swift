import Cocoa

/// The editable image. Coordinates are in points (image pixels / scale), y grows downward.
final class CanvasView: NSView, NSTextFieldDelegate {
    private enum Drag {
        case none
        case create(CGPoint)
        case move(CGPoint)
        case handleA, handleB
        case crop(CGPoint)
    }

    private(set) var state: DocState
    let scale: CGFloat
    private var undoStack: [DocState] = []
    private var redoStack: [DocState] = []
    private var pendingUndo: DocState?

    var tool: Tool = .step {
        didSet {
            if tool != .select && tool != oldValue { selected = nil }
            cropRect = nil
            window?.invalidateCursorRects(for: self)
            changed()
        }
    }
    var color: NSColor = palette[0].1
    var size: CGFloat = 4
    var nextStep = 1 { didSet { changed() } }
    var selected: Int? { didSet { needsDisplay = true } }
    /// True when there are edits not yet copied, saved or dragged out.
    var dirty = false
    var onChange: (() -> Void)?

    private var drag: Drag = .none
    private var draft: Annotation?
    private var cropRect: CGRect?
    private var pixCache: (src: CGImage, img: CGImage?)?
    private var textField: NSTextField?
    private var editingIndex: Int?
    private var editingOrigin = CGPoint.zero

    init(image: CGImage, scale: CGFloat) {
        state = DocState(image: image, annotations: [])
        self.scale = scale
        super.init(frame: CGRect(origin: .zero, size: CanvasView.pointSize(image, scale)))
    }

    required init?(coder: NSCoder) { fatalError() }

    static func pointSize(_ img: CGImage, _ scale: CGFloat) -> CGSize {
        CGSize(width: CGFloat(img.width) / scale, height: CGFloat(img.height) / scale)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func changed() {
        needsDisplay = true
        onChange?()
    }

    // MARK: State changes

    private func snapshot() {
        undoStack.append(state)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func mutate(undoable: Bool = true, _ f: (inout DocState) -> Void) {
        if undoable { snapshot() }
        f(&state)
        dirty = true
        changed()
    }

    private func restore(_ s: DocState) {
        let sizeChanged = s.image !== state.image
        state = s
        selected = nil
        recomputeNextStep()
        if sizeChanged { setFrameSize(CanvasView.pointSize(s.image, scale)) }
        dirty = true
        changed()
    }

    private func recomputeNextStep() {
        nextStep = (state.annotations.filter { $0.kind == .step }.map(\.number).max() ?? 0) + 1
    }

    @objc func undo(_ sender: Any?) {
        commitText()
        guard let prev = undoStack.popLast() else { NSSound.beep(); return }
        redoStack.append(state)
        restore(prev)
    }

    @objc func redo(_ sender: Any?) {
        commitText()
        guard let next = redoStack.popLast() else { NSSound.beep(); return }
        undoStack.append(state)
        restore(next)
    }

    @objc func delete(_ sender: Any?) { deleteSelected() }

    override func selectAll(_ sender: Any?) {}

    func deleteSelected() {
        guard let i = selected, i < state.annotations.count else { return }
        let removed = state.annotations[i]
        mutate { s in
            s.annotations.remove(at: i)
            // Close the gap: deleting 3 of 1–7 leaves 1–6. Skipped if another step shares
            // the number (a restarted sequence), so unrelated numbers don't shift.
            if removed.kind == .step, !s.annotations.contains(where: { $0.kind == .step && $0.number == removed.number }) {
                for j in s.annotations.indices where s.annotations[j].kind == .step && s.annotations[j].number > removed.number {
                    s.annotations[j].number -= 1
                }
            }
        }
        selected = nil
        if removed.kind == .step { recomputeNextStep() }
    }

    var stepNumbers: [Int] { state.annotations.filter { $0.kind == .step }.map(\.number) }

    /// Moves step `i` to position `n` and shifts the steps in between, like reordering a list:
    /// changing 7 to 3 turns the old 3–6 into 4–7.
    func renumberStep(at i: Int, to n: Int) {
        guard i < state.annotations.count, state.annotations[i].kind == .step, n >= 1 else { return }
        let old = state.annotations[i].number
        guard n != old else { return }
        let occupied = state.annotations.indices.contains { $0 != i && state.annotations[$0].kind == .step && state.annotations[$0].number == n }
        mutate { s in
            if occupied {
                for j in s.annotations.indices where j != i && s.annotations[j].kind == .step {
                    let m = s.annotations[j].number
                    if old < n, m > old, m <= n { s.annotations[j].number -= 1 }
                    if old > n, m >= n, m < old { s.annotations[j].number += 1 }
                }
            }
            s.annotations[i].number = n
        }
        recomputeNextStep()
    }

    private var digitBuffer = ""
    private var digitTime: TimeInterval = 0
    private var digitTarget: Int?
    private var digitBase: DocState?
    private var digitUndoDepth = 0

    func applyColor(_ c: NSColor) {
        color = c
        if let i = selected, i < state.annotations.count {
            mutate { $0.annotations[i].color = c }
        }
    }

    func applySize(_ s: CGFloat, final: Bool) {
        size = s
        guard let i = selected, i < state.annotations.count else { return }
        // A slider drag produces many events; record one undo step for the whole drag.
        if pendingUndo == nil { pendingUndo = state }
        mutate(undoable: false) { $0.annotations[i].size = s }
        if final, let p = pendingUndo {
            undoStack.append(p); redoStack.removeAll(); pendingUndo = nil
            onChange?()
        }
    }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): return canUndo
        case #selector(redo(_:)): return canRedo
        case #selector(delete(_:)): return selected != nil
        default: return true
        }
    }

    // MARK: Drawing

    private func pixelated() -> CGImage? {
        if let c = pixCache, c.src === state.image { return c.img }
        let img = Renderer.pixelate(state.image, blockPixels: max(8, 11 * scale))
        pixCache = (state.image, img)
        return img
    }

    private var hasBlur: Bool {
        state.annotations.contains { $0.kind == .blur } || draft?.kind == .blur
    }

    private func renderContent(showEditing: Bool) {
        Renderer.drawImage(state.image, in: bounds)
        let pix = hasBlur ? pixelated() : nil
        for (i, an) in state.annotations.enumerated() where !(showEditing && i == editingIndex) {
            Renderer.draw(an, pixelated: pix, canvas: bounds)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        renderContent(showEditing: true)
        if let d = draft { Renderer.draw(d, pixelated: pixelated(), canvas: bounds) }

        let zoom = enclosingScrollView?.magnification ?? 1
        if let i = selected, i < state.annotations.count {
            let an = state.annotations[i]
            let r = Renderer.bounds(an).insetBy(dx: -4 / zoom, dy: -4 / zoom)
            let p = NSBezierPath(rect: r)
            p.lineWidth = 1 / zoom
            p.setLineDash([4 / zoom, 3 / zoom], count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke(); p.stroke()
            for h in handles(for: an) { drawHandle(h, zoom: zoom) }
        }

        if let c = cropRect {
            let shade = NSBezierPath(rect: bounds)
            shade.append(NSBezierPath(rect: c))
            shade.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.5).setFill(); shade.fill()
            let border = NSBezierPath(rect: c)
            border.lineWidth = 1.5 / zoom
            border.setLineDash([6 / zoom, 4 / zoom], count: 2, phase: 0)
            NSColor.white.setStroke(); border.stroke()
            let label = NSAttributedString(string: " \(Int(c.width * scale)) × \(Int(c.height * scale)) ", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11 / zoom, weight: .semibold),
                .foregroundColor: NSColor.white, .backgroundColor: NSColor.black.withAlphaComponent(0.7),
            ])
            label.draw(at: CGPoint(x: c.minX, y: max(0, c.minY - 18 / zoom)))
        }
    }

    private func handles(for an: Annotation) -> [CGPoint] {
        switch an.kind {
        case .arrow, .rect, .ellipse, .highlight, .blur: return [an.a, an.b]
        case .step: return an.hasTail ? [an.b] : []
        case .text: return []
        }
    }

    private func drawHandle(_ p: CGPoint, zoom: CGFloat) {
        let r = 4.5 / zoom
        let dot = NSBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        NSColor.white.setFill(); dot.fill()
        dot.lineWidth = 1.5 / zoom
        NSColor.controlAccentColor.setStroke(); dot.stroke()
    }

    override func resetCursorRects() {
        switch tool {
        case .select: addCursorRect(bounds, cursor: .arrow)
        case .text: addCursorRect(bounds, cursor: .iBeam)
        default: addCursorRect(bounds, cursor: .crosshair)
        }
    }

    // MARK: Mouse

    private func point(_ e: NSEvent) -> CGPoint {
        let p = convert(e.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    private func hitIndex(_ p: CGPoint) -> Int? {
        state.annotations.indices.reversed().first { Renderer.hit(state.annotations[$0], p) }
    }

    override func mouseDown(with e: NSEvent) {
        if textField != nil { commitText(); return }
        window?.makeFirstResponder(self)
        let p = point(e)
        let zoom = enclosingScrollView?.magnification ?? 1

        // The dots on a selected annotation can be dragged with any tool.
        if let i = selected, i < state.annotations.count {
            let an = state.annotations[i]
            let slop = 7 / zoom
            if an.kind == .step, an.hasTail, hypot(p.x - an.b.x, p.y - an.b.y) <= slop {
                pendingUndo = state; drag = .handleB; return
            }
            if handles(for: an).count == 2 {
                if hypot(p.x - an.a.x, p.y - an.a.y) <= slop { pendingUndo = state; drag = .handleA; return }
                if hypot(p.x - an.b.x, p.y - an.b.y) <= slop { pendingUndo = state; drag = .handleB; return }
            }
        }

        switch tool {
        case .select:
            if let i = hitIndex(p) {
                selected = i
                if e.clickCount == 2, state.annotations[i].kind == .text { beginText(at: state.annotations[i].a, editing: i); return }
                pendingUndo = state
                drag = .move(p)
            } else {
                selected = nil
                drag = .none
            }
        case .text:
            if let i = hitIndex(p), state.annotations[i].kind == .text {
                beginText(at: state.annotations[i].a, editing: i)
            } else {
                beginText(at: p, editing: nil)
            }
        case .crop:
            selected = nil
            drag = .crop(p)
            cropRect = CGRect(origin: p, size: .zero)
        default:
            guard let kind = tool.kind else { return }
            // Clicking an existing number with the step tool (or whatever is already selected,
            // with any tool) grabs it to move instead of stacking a new item on top.
            if let i = hitIndex(p), (tool == .step && state.annotations[i].kind == .step) || i == selected {
                selected = i
                pendingUndo = state
                drag = .move(p)
                needsDisplay = true
                return
            }
            selected = nil
            drag = .create(p)
            draft = Annotation(kind: kind, a: p, b: p, color: color, size: size, number: nextStep)
        }
        needsDisplay = true
    }

    private func constrained(_ start: CGPoint, _ p: CGPoint, kind: Kind, shift: Bool) -> CGPoint {
        guard shift else { return p }
        let dx = p.x - start.x, dy = p.y - start.y
        switch kind {
        case .arrow, .step:
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let len = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * len, y: start.y + sin(angle) * len)
        default:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
    }

    private func beginPendingUndo() {
        if let p = pendingUndo {
            undoStack.append(p); redoStack.removeAll(); pendingUndo = nil
        }
    }

    override func mouseDragged(with e: NSEvent) {
        let p = point(e)
        let shift = e.modifierFlags.contains(.shift)
        switch drag {
        case .none: return
        case .create(let start):
            guard var d = draft else { return }
            d.b = constrained(start, p, kind: d.kind, shift: shift)
            if d.kind == .step { d.hasTail = hypot(d.b.x - start.x, d.b.y - start.y) > Renderer.badgeRadius(d.size) }
            draft = d
        case .move(let last):
            guard let i = selected else { return }
            beginPendingUndo()
            state.annotations[i].offset(p.x - last.x, p.y - last.y)
            drag = .move(p)
            dirty = true
        case .handleA, .handleB:
            guard let i = selected else { return }
            beginPendingUndo()
            var an = state.annotations[i]
            if case .handleA = drag { an.a = constrained(an.b, p, kind: an.kind, shift: shift) }
            else { an.b = constrained(an.a, p, kind: an.kind, shift: shift) }
            state.annotations[i] = an
            dirty = true
        case .crop(let start):
            cropRect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
        }
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        defer { drag = .none; draft = nil; pendingUndo = nil; changed() }
        switch drag {
        case .create:
            guard let d = draft else { return }
            let r = d.rect
            switch d.kind {
            case .step:
                // Placing a number that already exists inserts it: the old 3–7 become 4–8.
                let inserting = stepNumbers.contains(d.number)
                mutate { s in
                    if inserting {
                        for j in s.annotations.indices where s.annotations[j].kind == .step && s.annotations[j].number >= d.number {
                            s.annotations[j].number += 1
                        }
                    }
                    s.annotations.append(d)
                }
                if inserting { recomputeNextStep() } else { nextStep = d.number + 1 }
            case .arrow:
                guard hypot(d.b.x - d.a.x, d.b.y - d.a.y) >= 6 else { return }
                mutate { $0.annotations.append(d) }
            default:
                guard r.width >= 4 || r.height >= 4 else { return }
                mutate { $0.annotations.append(d) }
            }
            selected = state.annotations.count - 1
        case .crop:
            if let c = cropRect { applyCrop(c) }
            cropRect = nil
        default:
            break
        }
    }

    private func applyCrop(_ c: CGRect) {
        let r = c.intersection(bounds)
        guard r.width >= 8, r.height >= 8 else { return }
        let px = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale).integral
        guard let cropped = state.image.cropping(to: px) else { return }
        let ox = px.minX / scale, oy = px.minY / scale
        mutate { s in
            s.image = cropped
            for i in s.annotations.indices { s.annotations[i].offset(-ox, -oy) }
        }
        setFrameSize(CanvasView.pointSize(cropped, scale))
        tool = .select
    }

    // MARK: Right-click menu

    override func menu(for event: NSEvent) -> NSMenu? {
        commitText()
        let p = point(event)
        guard let i = hitIndex(p) else { return nil }
        selected = i
        let an = state.annotations[i]
        let m = NSMenu()
        if an.kind == .step {
            let change = NSMenuItem(title: "Change Number To", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let top = max(stepNumbers.max() ?? 1, an.number)
            for n in 1...max(top, 1) {
                let it = NSMenuItem(title: "\(n)", action: #selector(menuRenumber(_:)), keyEquivalent: "")
                it.target = self
                it.tag = n
                it.state = n == an.number ? .on : .off
                sub.addItem(it)
            }
            change.submenu = sub
            m.addItem(change)
            let tip = NSMenuItem(title: "Tip: select a number and type a new one", action: nil, keyEquivalent: "")
            tip.isEnabled = false
            m.addItem(tip)
            m.addItem(.separator())
        }
        if an.kind == .text {
            let edit = NSMenuItem(title: "Edit Text", action: #selector(menuEditText(_:)), keyEquivalent: "")
            edit.target = self
            m.addItem(edit)
            m.addItem(.separator())
        }
        let del = NSMenuItem(title: an.kind == .step ? "Delete (later steps move up)" : "Delete", action: #selector(menuDelete(_:)), keyEquivalent: "")
        del.target = self
        m.addItem(del)
        return m
    }

    @objc private func menuRenumber(_ sender: NSMenuItem) {
        if let i = selected { renumberStep(at: i, to: sender.tag) }
    }

    @objc private func menuDelete(_ sender: NSMenuItem) { deleteSelected() }

    @objc private func menuEditText(_ sender: NSMenuItem) {
        if let i = selected, i < state.annotations.count { beginText(at: state.annotations[i].a, editing: i) }
    }

    // MARK: Keyboard

    override func keyDown(with e: NSEvent) {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        switch e.keyCode {
        case 51, 117: deleteSelected(); return
        case 53:
            if cropRect != nil || draft != nil { cropRect = nil; draft = nil; drag = .none }
            else { selected = nil }
            needsDisplay = true
            return
        case 123, 124, 125, 126:
            guard let i = selected else { break }
            let step: CGFloat = mods.contains(.shift) ? 10 : 1
            let d: (CGFloat, CGFloat) = [123: (-step, 0), 124: (step, 0), 125: (0, step), 126: (0, -step)][e.keyCode]!
            mutate { $0.annotations[i].offset(d.0, d.1) }
            return
        default: break
        }
        if mods.isEmpty || mods == .shift, let ch = e.charactersIgnoringModifiers?.lowercased() {
            if let t = Tool.allCases.first(where: { $0.key == ch }) { tool = t; return }
            if let digit = Int(ch) {
                // With a step selected, typing a number changes that step (two digits work too).
                if let i = selected, i < state.annotations.count, state.annotations[i].kind == .step {
                    let now = e.timestamp
                    let continuing = i == digitTarget && now - digitTime < 0.9 && digitBuffer.count == 1
                    if continuing, let base = digitBase, undoStack.count == digitUndoDepth + 1 {
                        // Second digit: undo the one-digit change first so "1","2" means 12, not 1 then 12.
                        undoStack.removeLast()
                        state = base
                    }
                    digitBuffer = continuing ? digitBuffer + ch : ch
                    if !continuing { digitBase = state; digitUndoDepth = undoStack.count }
                    digitTarget = i
                    digitTime = now
                    if let n = Int(digitBuffer), n >= 1 { renumberStep(at: i, to: n) }
                    return
                }
                if digit >= 1 { nextStep = digit; tool = .step; return }
            }
        }
        super.keyDown(with: e)
    }

    // MARK: Text editing

    private func beginText(at p: CGPoint, editing index: Int?) {
        commitText()
        var an = Annotation(kind: .text, a: p, b: p, color: color, size: size)
        if let i = index { an = state.annotations[i]; selected = i }
        editingIndex = index
        editingOrigin = an.a

        let field = NSTextField(string: an.text)
        field.font = Renderer.textFont(an.size)
        field.textColor = an.color
        field.backgroundColor = Renderer.textBacking(an.color)
        field.drawsBackground = true
        field.isBordered = false
        field.focusRingType = .none
        field.usesSingleLineMode = false
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = self
        field.placeholderString = "Type here"
        field.frame = CGRect(x: an.a.x + Renderer.textPad - 2, y: an.a.y + Renderer.textPad - 1, width: 160, height: 30)
        addSubview(field)
        textField = field
        resizeTextField()
        window?.makeFirstResponder(field)
        needsDisplay = true
    }

    private func resizeTextField() {
        guard let f = textField else { return }
        let probe = Annotation(kind: .text, a: .zero, b: .zero, color: color, size: f.font.map { ($0.pointSize - 12) / 2 } ?? size,
                               text: f.stringValue.isEmpty ? "Type here" : f.stringValue + "W")
        let r = Renderer.textRect(probe)
        f.setFrameSize(CGSize(width: max(80, r.width), height: r.height - Renderer.textPad * 2 + 4))
    }

    func controlTextDidChange(_ obj: Notification) { resizeTextField() }

    func controlTextDidEndEditing(_ obj: Notification) { commitText() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { commitText(); return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { cancelText(); return true }
        return false
    }

    private func cancelText() {
        guard let f = textField else { return }
        textField = nil
        f.removeFromSuperview()
        editingIndex = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func commitText() {
        guard let f = textField else { return }
        textField = nil
        let s = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        f.removeFromSuperview()
        if let i = editingIndex, i < state.annotations.count {
            if s.isEmpty { mutate { $0.annotations.remove(at: i) }; selected = nil }
            else if s != state.annotations[i].text { mutate { $0.annotations[i].text = s } }
        } else if !s.isEmpty {
            mutate { $0.annotations.append(Annotation(kind: .text, a: editingOrigin, b: editingOrigin, color: color, size: size, text: s)) }
            selected = state.annotations.count - 1
        }
        editingIndex = nil
        window?.makeFirstResponder(self)
        changed()
    }

    // MARK: Export

    /// The marked-up image at full resolution, with Retina DPI kept so it pastes at the right size.
    func renderedPNG(commitEditing: Bool = true) -> Data? {
        if commitEditing { commitText() }
        let pw = state.image.width, ph = state.image.height
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let base = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let cg = base.cgContext
        cg.translateBy(x: 0, y: CGFloat(ph))
        cg.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        renderContent(showEditing: false)
        NSGraphicsContext.restoreGraphicsState()
        rep.size = bounds.size
        return rep.representation(using: .png, properties: [:])
    }
}
