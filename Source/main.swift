import Cocoa
import Carbon
import ImageIO
import ServiceManagement

struct Hotkey {
    let code: Int
    let mods: Int
    let name: String
}

/// Picked to avoid macOS's own ⌘⇧3/4/5 screenshot keys.
let hotkeyChoices: [Hotkey] = [
    Hotkey(code: kVK_ANSI_2, mods: cmdKey | shiftKey, name: "⇧⌘2"),
    Hotkey(code: kVK_ANSI_S, mods: controlKey | shiftKey, name: "⌃⇧S"),
    Hotkey(code: kVK_ANSI_S, mods: cmdKey | optionKey, name: "⌥⌘S"),
    Hotkey(code: kVK_ANSI_S, mods: cmdKey | optionKey | controlKey, name: "⌃⌥⌘S"),
    Hotkey(code: kVK_F13, mods: 0, name: "F13"),
]

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var capturesFolder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mac Capture Studio", isDirectory: true)
    }

    private var statusItem: NSStatusItem!
    private var editors: [EditorController] = []
    private var hotkeyRef: EventHotKeyRef?
    private var capturing = false
    private var hotkeyIndex: Int {
        get { min(max(UserDefaults.standard.integer(forKey: "hotkeyIndex"), 0), hotkeyChoices.count - 1) }
        set { UserDefaults.standard.set(newValue, forKey: "hotkeyIndex") }
    }
    private var hotkey: Hotkey { hotkeyChoices[hotkeyIndex] }
    private let statusMenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Mac Capture Studio")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        installHotkeyHandler()
        registerHotkey(showErrors: true)

        if !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            DispatchQueue.main.async { self.welcome() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Double-clicking the app again starts a capture, which is usually what was wanted.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { capture(nil) }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { openEditor(url: url, name: url.deletingPathExtension().lastPathComponent) }
    }

    // MARK: Menus

    private func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = target
        return i
    }

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            top.submenu = m
            main.addItem(top)
            return m
        }
        _ = add("Mac Capture Studio", [
            item("About Mac Capture Studio", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide Mac Capture Studio", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            item("Quit Mac Capture Studio", #selector(NSApplication.terminate(_:)), "q"),
        ])
        let newCapture = item("New Capture", #selector(capture(_:)), "n", target: self)
        _ = add("File", [
            newCapture,
            item("New from Clipboard", #selector(openClipboard(_:)), "n", [.command, .shift], target: self),
            item("Open…", #selector(openImage(_:)), "o", target: self),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
            item("Save", #selector(EditorController.saveDocument(_:)), "s"),
            item("Save As…", #selector(EditorController.saveDocumentAs(_:)), "s", [.command, .shift]),
            item("Copy and Close", #selector(EditorController.copyAndClose(_:)), "\r"),
            item("Show in Finder", #selector(EditorController.showInFinder(_:)), "r"),
        ])
        _ = add("Edit", [
            item("Undo", #selector(CanvasView.undo(_:)), "z"),
            item("Redo", #selector(CanvasView.redo(_:)), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Delete", #selector(CanvasView.delete(_:))),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        _ = add("View", [
            item("Zoom In", #selector(EditorController.zoomIn(_:)), "="),
            item("Zoom Out", #selector(EditorController.zoomOut(_:)), "-"),
            item("Actual Size", #selector(EditorController.zoomActual(_:)), "0"),
            item("Zoom to Fit", #selector(EditorController.zoomToFit(_:)), "9"),
        ])
        let window = add("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.windowsMenu = window
        return main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        menu.removeAllItems()
        let cap = item("Capture Area or Window   \(hotkey.name)", #selector(capture(_:)), target: self)
        menu.addItem(cap)
        menu.addItem(item("Capture in 3 Seconds", #selector(captureDelayed(_:)), target: self))
        menu.addItem(item("New from Clipboard", #selector(openClipboard(_:)), target: self))
        menu.addItem(item("Open Image…", #selector(openImage(_:)), target: self))
        menu.addItem(.separator())
        menu.addItem(item("Show Captures Folder", #selector(showFolder(_:)), target: self))

        let keys = NSMenu()
        for (i, h) in hotkeyChoices.enumerated() {
            let k = item(h.name, #selector(chooseHotkey(_:)), target: self)
            k.tag = i
            k.state = i == hotkeyIndex ? .on : .off
            keys.addItem(k)
        }
        let keysItem = NSMenuItem(title: "Capture Shortcut", action: nil, keyEquivalent: "")
        keysItem.submenu = keys
        menu.addItem(keysItem)

        let login = item("Open at Login", #selector(toggleLogin(_:)), target: self)
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("How to Use…", #selector(showHelp(_:)), target: self))
        menu.addItem(.separator())
        menu.addItem(item("Quit Mac Capture Studio", #selector(NSApplication.terminate(_:)), "q"))
    }

    // MARK: Global hotkey (Carbon: no Accessibility permission needed)

    private func installHotkeyHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { app.capture(nil) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    private func registerHotkey(showErrors: Bool) {
        if let r = hotkeyRef { UnregisterEventHotKey(r); hotkeyRef = nil }
        let h = hotkey
        let status = RegisterEventHotKey(UInt32(h.code), UInt32(h.mods), EventHotKeyID(signature: 0x4D435331, id: 1),
                                         GetApplicationEventTarget(), 0, &hotkeyRef)
        if status != noErr && showErrors {
            let a = NSAlert()
            a.messageText = "\(h.name) is already used by another app"
            a.informativeText = "Pick a different shortcut from the menu bar icon › Capture Shortcut."
            a.runModal()
        }
    }

    @objc private func chooseHotkey(_ sender: NSMenuItem) {
        hotkeyIndex = sender.tag
        registerHotkey(showErrors: true)
    }

    // MARK: Capture

    private func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if !UserDefaults.standard.bool(forKey: "askedScreenAccess") {
            UserDefaults.standard.set(true, forKey: "askedScreenAccess")
            _ = CGRequestScreenCaptureAccess()
        }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Allow screen recording"
        a.informativeText = "macOS needs your OK before Mac Capture Studio can take screenshots.\n\n1. Click Open System Settings.\n2. Turn on Mac Capture Studio under Screen & System Audio Recording.\n3. Come back and click Restart App."
        a.addButton(withTitle: "Open System Settings")
        a.addButton(withTitle: "Restart App")
        a.addButton(withTitle: "Cancel")
        switch a.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        case .alertSecondButtonReturn:
            relaunch()
        default: break
        }
        return false
    }

    private func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }

    @objc func capture(_ sender: Any?) { startCapture(delay: 0) }
    @objc func captureDelayed(_ sender: Any?) { startCapture(delay: 3) }

    private func startCapture(delay: Int) {
        guard !capturing else { return }
        guard ensurePermission() else { return }
        capturing = true
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("capture-\(UUID().uuidString).png")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i: drag an area, or press Space to pick a window. -o: no window shadow. -x: no sound.
        var args = ["-i", "-o", "-x"]
        if delay > 0 { args += ["-T", "\(delay)"] }
        p.arguments = args + [tmp.path]
        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                self.capturing = false
                self.finishCapture(tmp)
            }
        }
        do { try p.run() } catch {
            capturing = false
            NSAlert(error: error).runModal()
        }
    }

    private func finishCapture(_ tmp: URL) {
        // No file means the user pressed Esc.
        guard FileManager.default.fileExists(atPath: tmp.path) else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let name = "Capture \(f.string(from: Date()))"
        let folder = AppDelegate.capturesFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent("\(name).png")
        do { try FileManager.default.moveItem(at: tmp, to: dest) } catch {
            openEditor(url: tmp, name: name); return
        }
        openEditor(url: dest, name: name)
    }

    // MARK: Editors

    private func openEditor(url: URL, name: String) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            let a = NSAlert(); a.messageText = "Couldn’t open “\(url.lastPathComponent)” as an image."; a.runModal()
            return
        }
        var scale: CGFloat = 1
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let dpi = props[kCGImagePropertyDPIWidth] as? Double, dpi > 72 {
            scale = CGFloat(dpi / 72)
        }
        openEditor(image: img, scale: scale, name: name)
    }

    private func openEditor(image: CGImage, scale: CGFloat, name: String) {
        let ed = EditorController(image: image, scale: scale, name: name)
        ed.onClose = { [weak self] e in
            guard let self else { return }
            self.editors.removeAll { $0 === e }
            if self.editors.isEmpty { NSApp.setActivationPolicy(.accessory) }
        }
        editors.append(ed)
        NSApp.setActivationPolicy(.regular)
        ed.showAndFit()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openImage(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.directoryURL = AppDelegate.capturesFolder
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { openEditor(url: url, name: url.deletingPathExtension().lastPathComponent) }
    }

    @objc private func openClipboard(_ sender: Any?) {
        guard let ns = NSImage(pasteboard: NSPasteboard.general),
              let rep = ns.representations.first,
              let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            let a = NSAlert(); a.messageText = "There’s no image on the clipboard."; a.runModal()
            return
        }
        let scale = rep.size.width > 0 ? max(1, CGFloat(rep.pixelsWide) / rep.size.width) : 1
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        openEditor(image: cg, scale: scale, name: "Clipboard \(f.string(from: Date()))")
    }

    @objc private func showFolder(_ sender: Any?) {
        try? FileManager.default.createDirectory(at: AppDelegate.capturesFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(AppDelegate.capturesFolder)
    }

    @objc private func toggleLogin(_ sender: Any?) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: Help

    private var helpText: String {
        """
        Press \(hotkey.name) anywhere. Drag across what you want, or press Space and click a window. Esc cancels.

        The editor opens right away:
        • Step numbers (S): click to drop 1, 2, 3… in order. Drag to add a pointer arrow. Type 1–9 to restart numbering.
        • Arrow (A), Box (R), Circle (O), Highlight (H), Blur (B), Text (T), Crop (C), Select (V).
        • Click a color or move Size to restyle the selected item. Delete removes it.

        Send it fast:
        • ⌘C copies, and ⌘Return copies and closes. Then paste into an email or chat.
        • Or drag the “Drag” box into Mail, Slack or Messages.
        • Captures are kept in Pictures › Mac Capture Studio.
        """
    }

    private func welcome() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Mac Capture Studio is in your menu bar"
        a.informativeText = helpText + "\n\nThe first capture asks for Screen Recording permission."
        a.addButton(withTitle: "Take a Capture Now")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn { capture(nil) }
    }

    @objc private func showHelp(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "How to use Mac Capture Studio"
        a.informativeText = helpText
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
