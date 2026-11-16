import Cocoa
import Carbon
import ImageIO
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var capturesFolder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mac Capture Studio", isDirectory: true)
    }

    private var statusItem: NSStatusItem!
    private var editors: [EditorController] = []
    private var hotkeyRef: EventHotKeyRef?
    private var capturing = false
    private var hotkey = Hotkey.saved
    private var recorder: ShortcutRecorder?
    private let statusMenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Show button descriptions quickly when hovering (the macOS default wait is long).
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 350, "autoCopy": true, "liveClipboard": false])
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
            .separator(),
            item("Hide Capture History", #selector(EditorController.toggleHistory(_:)), "h", [.command, .shift]),
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
        keys.addItem(item("Choose Your Own Shortcut…", #selector(recordHotkey(_:)), target: self))
        keys.addItem(.separator())
        let current = item("Current: \(hotkey.name)", nil)
        current.isEnabled = false
        keys.addItem(current)
        for (i, h) in hotkeyPresets.enumerated() where h != hotkey {
            let k = item(h.name, #selector(chooseHotkey(_:)), target: self)
            k.tag = i
            keys.addItem(k)
        }
        let keysItem = NSMenuItem(title: "Capture Shortcut", action: nil, keyEquivalent: "")
        keysItem.submenu = keys
        menu.addItem(keysItem)

        let auto = item("Copy Each Capture to Clipboard", #selector(toggleAutoCopy(_:)), target: self)
        auto.state = UserDefaults.standard.bool(forKey: "autoCopy") ? .on : .off
        auto.toolTip = "Puts every new capture on the clipboard the moment you take it, ready to paste."
        menu.addItem(auto)
        let live = item("Keep Clipboard Updated While Marking Up", #selector(toggleLiveClipboard(_:)), target: self)
        live.state = UserDefaults.standard.bool(forKey: "liveClipboard") ? .on : .off
        live.toolTip = "Every change in the editor (numbers, arrows, blur…) is copied automatically, so you can paste without pressing ⌘C."
        menu.addItem(live)

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

    private func unregisterHotkey() {
        if let r = hotkeyRef { UnregisterEventHotKey(r); hotkeyRef = nil }
    }

    /// Registers `h` as the live global hotkey. Returns false if macOS or another app already owns it.
    @discardableResult
    private func register(_ h: Hotkey) -> Bool {
        unregisterHotkey()
        return RegisterEventHotKey(UInt32(h.code), UInt32(h.mods), EventHotKeyID(signature: 0x4D435331, id: 1),
                                   GetApplicationEventTarget(), 0, &hotkeyRef) == noErr
    }

    private func registerHotkey(showErrors: Bool) {
        let h = hotkey
        if !register(h) && showErrors {
            let a = NSAlert()
            a.messageText = "\(h.name) is already used by another app"
            a.informativeText = "Pick a different shortcut from the menu bar icon › Capture Shortcut."
            a.runModal()
        }
    }

    @objc private func chooseHotkey(_ sender: NSMenuItem) {
        hotkey = hotkeyPresets[sender.tag]
        Hotkey.saved = hotkey
        registerHotkey(showErrors: true)
    }

    @objc private func recordHotkey(_ sender: Any?) {
        if let r = recorder { r.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        // Free the current shortcut so pressing it again is heard by the recorder, not treated as a capture.
        unregisterHotkey()
        let r = ShortcutRecorder(current: hotkey)
        r.tryRegister = { [weak self] h in
            guard let self else { return false }
            let ok = self.register(h)
            self.unregisterHotkey()
            return ok
        }
        r.onFinish = { [weak self] chosen in
            guard let self else { return }
            if let chosen {
                self.hotkey = chosen
                Hotkey.saved = chosen
            }
            self.registerHotkey(showErrors: true)
            self.recorder = nil
        }
        recorder = r
        r.start()
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
        NotificationCenter.default.post(name: .capturesChanged, object: nil)
        let copied = UserDefaults.standard.bool(forKey: "autoCopy")
        if copied, let data = try? Data(contentsOf: dest) { EditorController.putOnClipboard(data) }
        openEditor(url: dest, name: name)
        if copied {
            editors.last?.announce(UserDefaults.standard.bool(forKey: "liveClipboard")
                ? "On your clipboard. Markup is copied as you go."
                : "Copied to clipboard. Mark it up, then ⌘C to copy again.")
        }
    }

    // MARK: Editors

    func openEditor(url: URL, name: String) {
        if let existing = editors.first(where: { $0.sourceURL == url }) {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let (img, scale) = ImageLoader.load(url) else {
            let a = NSAlert(); a.messageText = "Couldn’t open “\(url.lastPathComponent)” as an image."; a.runModal()
            return
        }
        openEditor(image: img, scale: scale, name: name, sourceURL: url)
    }

    private func openEditor(image: CGImage, scale: CGFloat, name: String, sourceURL: URL? = nil) {
        let ed = EditorController(image: image, scale: scale, name: name, sourceURL: sourceURL)
        ed.onOpenNewWindow = { [weak self] url in self?.openEditor(url: url, name: CaptureEntry.baseName(of: url)) }
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

    @objc private func toggleAutoCopy(_ sender: Any?) {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "autoCopy"), forKey: "autoCopy")
    }

    @objc private func toggleLiveClipboard(_ sender: Any?) {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "liveClipboard"), forKey: "liveClipboard")
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
        • Step numbers (S): click to drop 1, 2, 3… in order. Drag an existing number to move it. Drag from empty space to add a pointer arrow. Type 1–9 to restart numbering.
        • Arrow (A), Box (R), Circle (O), Highlight (H), Blur (B), Text (T), Crop (C), Select (V).
        • Click a color or move Size to restyle the selected item. Delete removes it.

        Send it fast:
        • Each new capture is already on your clipboard, so you can paste right away.
        • After marking up, ⌘C copies again, and ⌘Return copies and closes. Or turn on “Keep Clipboard Updated While Marking Up” in the menu bar so the markup is copied as you go.
        • Or drag the “Drag” box into Mail, Slack or Messages.
        • Every capture is kept in Pictures › Mac Capture Studio and shown in the history strip under the image. Click one to reopen it, or right-click for more.
        • Hover over any button to see what it does.
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
