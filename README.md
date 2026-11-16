# Mac Capture Studio

A native macOS screenshot and markup app for quick how-to images. Press a hotkey, drag over part of the screen, and the capture opens straight in an editor. Drop numbered steps and arrows on it, then copy or drag it into an email or chat.

## Use it

1. Open **Mac Capture Studio** from Applications. It lives in the menu bar (camera icon), not the Dock.
2. Press **⇧⌘2** anywhere. Drag across what you want, or press **Space** and click a window. **Esc** cancels.
3. The first time, macOS asks for **Screen Recording** permission. Turn on Mac Capture Studio under System Settings › Privacy & Security › Screen & System Audio Recording, then choose **Restart App**.

### Editor

| Tool | Key | What it does |
|---|---|---|
| Step number | S | Click to drop 1, 2, 3… in order. Drag from the spot to a target to add a pointer arrow. Type **1–9** to restart numbering, or use the Next stepper. |
| Arrow | A | Drag from tail to point. Shift snaps to 45°. |
| Box / Circle | R / O | Outline something. Shift for a square or perfect circle. |
| Highlight | H | Translucent marker over an area. |
| Blur | B | Pixelates anything private. |
| Text | T | Click and type. Return finishes, Option-Return adds a line. |
| Crop | C | Drag the area to keep. |
| Select | V | Move items, drag the dots to reshape, Delete removes, double-click text to edit. |

Picking a color or moving **Size** restyles the selected item. Undo and redo cover everything, crop included.

### Sending it

- **⌘C** copies the marked-up image. **⌘Return** copies it and closes the editor.
- Drag the **Drag** box into Mail, Slack, Messages or a Finder folder.
- **⌘S** saves to `~/Pictures/Mac Capture Studio`. Every capture is also kept there, and closing an editor with unsaved markup saves a “marked up” copy instead of discarding it.

### Menu bar options

Capture in 3 seconds (for open menus), New from Clipboard, Open Image…, Show Captures Folder, Capture Shortcut (⇧⌘2, ⌃⇧S, ⌥⌘S, ⌃⌥⌘S or F13), Open at Login, and How to Use.

## Build

Needs Xcode or the Command Line Tools. No other dependencies.

```bash
./build.sh            # builds build/Mac Capture Studio.app (universal: Apple silicon + Intel)
./build.sh --install  # also copies it to /Applications and opens it
```

The app is signed ad hoc (not notarized). After each rebuild macOS may ask for Screen Recording permission again. If captures come out showing only the desktop wallpaper, remove the app from that permission list, add it back, and restart the app.

## Code

- `Source/main.swift`: menu bar item, global hotkey (Carbon, so no Accessibility permission is needed), capture via `/usr/sbin/screencapture -i`, menus.
- `Source/Editor.swift`: editor window, toolbar, copy, save and drag-out.
- `Source/Canvas.swift`: the drawing surface: mouse and keyboard handling, undo, crop, export.
- `Source/Model.swift`: tools, annotation model and all drawing code (shared by the screen and the export).
- `Tools/MakeIcon.swift`: draws the app icon at build time.

The original Electron prototype is in git history (before the `claude/native-step-capture` branch).
