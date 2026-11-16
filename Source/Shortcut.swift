import Cocoa
import Carbon

struct Hotkey: Equatable {
    let code: Int
    let mods: Int   // Carbon modifier mask (cmdKey, optionKey, controlKey, shiftKey)
    let name: String

    static let defaultKey = Hotkey(code: kVK_ANSI_2, mods: cmdKey | shiftKey, name: "⇧⌘2")

    /// Remembered choice. Older builds stored only a preset index, which is still honored.
    static var saved: Hotkey {
        get {
            let d = UserDefaults.standard
            if d.object(forKey: "hotkeyCode") != nil, let name = d.string(forKey: "hotkeyName") {
                return Hotkey(code: d.integer(forKey: "hotkeyCode"), mods: d.integer(forKey: "hotkeyMods"), name: name)
            }
            if d.object(forKey: "hotkeyIndex") != nil {
                let legacy = [defaultKey,
                              Hotkey(code: kVK_ANSI_S, mods: controlKey | shiftKey, name: "⌃⇧S"),
                              Hotkey(code: kVK_ANSI_S, mods: cmdKey | optionKey, name: "⌥⌘S"),
                              Hotkey(code: kVK_ANSI_S, mods: cmdKey | optionKey | controlKey, name: "⌃⌥⌘S"),
                              Hotkey(code: kVK_F13, mods: 0, name: "F13")]
                return legacy[min(max(d.integer(forKey: "hotkeyIndex"), 0), legacy.count - 1)]
            }
            return defaultKey
        }
        set {
            let d = UserDefaults.standard
            d.set(newValue.code, forKey: "hotkeyCode")
            d.set(newValue.mods, forKey: "hotkeyMods")
            d.set(newValue.name, forKey: "hotkeyName")
        }
    }

    static func carbonMods(_ f: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if f.contains(.command) { m |= cmdKey }
        if f.contains(.option) { m |= optionKey }
        if f.contains(.control) { m |= controlKey }
        if f.contains(.shift) { m |= shiftKey }
        return m
    }

    static func modSymbols(_ m: Int) -> String {
        (m & controlKey != 0 ? "⌃" : "") + (m & optionKey != 0 ? "⌥" : "") + (m & shiftKey != 0 ? "⇧" : "") + (m & cmdKey != 0 ? "⌘" : "")
    }

    static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
        kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_Grave: "`",
    ]

    static func keyName(_ e: NSEvent) -> String {
        let code = Int(e.keyCode)
        if let f = functionKeys[code] { return f }
        if let s = specialKeys[code] { return s }
        let ch = e.characters(byApplyingModifiers: [])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ch.isEmpty ? "Key \(code)" : ch.uppercased()
    }
}

/// Picked to avoid macOS's own ⌘⇧3/4/5 screenshot keys.
let hotkeyPresets: [Hotkey] = [
    Hotkey.defaultKey,
    Hotkey(code: kVK_ANSI_Grave, mods: controlKey, name: "⌃`"),
    Hotkey(code: kVK_ANSI_1, mods: controlKey, name: "⌃1"),
    Hotkey(code: kVK_ANSI_S, mods: controlKey | shiftKey, name: "⌃⇧S"),
    Hotkey(code: kVK_F13, mods: 0, name: "F13"),
]

/// A small window that listens for the next key press and offers it as the capture shortcut.
final class ShortcutRecorder: NSWindowController, NSWindowDelegate {
    /// Returns true if the shortcut could be registered.
    var tryRegister: ((Hotkey) -> Bool)?
    var onFinish: ((Hotkey?) -> Void)?

    private let display = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton(title: "Use This Shortcut", target: nil, action: nil)
    private var monitor: Any?
    private var candidate: Hotkey?
    private var finished = false

    init(current: Hotkey) {
        let win = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 440, height: 300), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Capture Shortcut"
        win.isReleasedWhenClosed = false
        win.level = .floating
        super.init(window: win)
        win.delegate = self

        let title = NSTextField(labelWithString: "Press the keys you want to use")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let sub = NSTextField(wrappingLabelWithString: "Hold one modifier (⌃ Control, ⌥ Option or ⌘ Command) and press one key. A function key like F13 works on its own. Easy two-key ideas: ⌃`  ⌃1  ⌃Q  ⌥`  ⌥1.")
        sub.textColor = .secondaryLabelColor
        sub.font = .systemFont(ofSize: 12)

        display.stringValue = current.name
        display.font = .monospacedSystemFont(ofSize: 30, weight: .semibold)
        display.alignment = .center
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 10
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor
        box.contentView = display
        box.heightAnchor.constraint(equalToConstant: 64).isActive = true

        message.stringValue = "Current shortcut: \(current.name). Press a new one now, or Esc to keep it."
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor

        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"
        saveButton.isEnabled = false
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        let reset = NSButton(title: "Reset to ⇧⌘2", target: self, action: #selector(resetDefault))
        let buttons = NSStackView(views: [reset, NSView(), cancel, saveButton])
        buttons.distribution = .fill

        let stack = NSStackView(views: [title, sub, box, message, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        win.contentView = stack
        for v in [sub, box, message, buttons] { v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true }
        stack.widthAnchor.constraint(equalToConstant: 440).isActive = true
        win.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    func start() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.window else { return e }
            self.handle(e)
            return nil
        }
    }

    private func handle(_ e: NSEvent) {
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(e.keyCode)
        if code == kVK_Escape && flags.isEmpty { cancel(); return }
        if code == kVK_Return && flags.isEmpty, candidate != nil { save(); return }

        let mods = Hotkey.carbonMods(flags)
        let key = Hotkey.keyName(e)
        let hk = Hotkey(code: code, mods: mods, name: Hotkey.modSymbols(mods) + key)
        display.stringValue = hk.name
        let isFKey = Hotkey.functionKeys[code] != nil
        let hasMain = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)

        func reject(_ why: String) {
            candidate = nil
            saveButton.isEnabled = false
            message.textColor = .systemRed
            message.stringValue = why
        }

        if !hasMain && !isFKey {
            return reject(flags.contains(.shift)
                ? "Shift alone would block typing capital letters. Add ⌃, ⌥ or ⌘."
                : "A single key would stop working for typing. Hold ⌃, ⌥ or ⌘ too, or use a function key like F13.")
        }
        let blocked: [(Int, Int, String)] = [
            (kVK_ANSI_Q, cmdKey, "quits apps"), (kVK_ANSI_W, cmdKey, "closes windows"), (kVK_Tab, cmdKey, "switches apps"),
            (kVK_Space, cmdKey, "opens Spotlight"), (kVK_Space, controlKey, "switches keyboard language"),
            (kVK_ANSI_3, cmdKey | shiftKey, "is macOS’s screenshot key"), (kVK_ANSI_4, cmdKey | shiftKey, "is macOS’s screenshot key"),
            (kVK_ANSI_5, cmdKey | shiftKey, "is macOS’s screenshot key"),
            (kVK_LeftArrow, controlKey, "switches desktops"), (kVK_RightArrow, controlKey, "switches desktops"),
            (kVK_UpArrow, controlKey, "opens Mission Control"), (kVK_DownArrow, controlKey, "shows app windows"),
            (kVK_ANSI_C, cmdKey, "is Copy"), (kVK_ANSI_V, cmdKey, "is Paste"), (kVK_ANSI_X, cmdKey, "is Cut"),
            (kVK_ANSI_Z, cmdKey, "is Undo"), (kVK_ANSI_A, cmdKey, "is Select All"), (kVK_ANSI_S, cmdKey, "is Save"),
        ]
        if let b = blocked.first(where: { $0.0 == code && $0.1 == mods }) {
            return reject("\(hk.name) \(b.2) everywhere on your Mac. Pick another.")
        }
        guard tryRegister?(hk) == true else {
            return reject("\(hk.name) is already taken by macOS or another app. Pick another.")
        }

        candidate = hk
        saveButton.isEnabled = true
        var note = "Press Return or click Use This Shortcut."
        if mods == cmdKey { note = "Heads up: \(hk.name) will stop doing its usual job in other apps. " + note }
        else if mods == optionKey || mods == optionKey | shiftKey { note = "Heads up: you won’t be able to type the special character for \(hk.name) any more. " + note }
        message.textColor = mods == cmdKey || mods & optionKey != 0 && mods & (cmdKey | controlKey) == 0 ? .systemOrange : .systemGreen
        message.stringValue = "✓ \(hk.name) is available. " + note
    }

    @objc private func save() {
        guard let c = candidate else { return }
        finish(c)
    }

    @objc private func cancel() { finish(nil) }

    @objc private func resetDefault() {
        guard tryRegister?(Hotkey.defaultKey) == true else { NSSound.beep(); return }
        finish(Hotkey.defaultKey)
    }

    private func finish(_ result: Hotkey?) {
        guard !finished else { return }
        finished = true
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        onFinish?(result)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) { finish(nil) }
}
