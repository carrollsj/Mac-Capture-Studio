# Mac Capture Studio

A native macOS screenshot and markup app for quick how-to images. Press a hotkey, drag over part of the screen, and the capture opens straight in an editor. Drop numbered steps and arrows on it, then copy or drag it into an email or chat.

## Use it

1. Open **Mac Capture Studio** from Applications. It lives in the menu bar (camera icon), not the Dock.
2. Press **⇧⌘2** anywhere. Drag across what you want, or press **Space** and click a window. **Esc** cancels.
3. The first time, macOS asks for **Screen Recording** permission. Turn on Mac Capture Studio under System Settings › Privacy & Security › Screen & System Audio Recording, then choose **Restart App**.

### Editor

| Tool | Key | What it does |
|---|---|---|
| Step number | S | Click empty space to drop 1, 2, 3… in order. Drag an existing number to move it. Drag from empty space to a target to add a pointer arrow. Type **1–9** to restart numbering, or use the Next stepper. |
| Arrow | A | Drag from tail to point. Shift snaps to 45°. |
| Box / Circle | R / O | Outline something. Shift for a square or perfect circle. |
| Highlight | H | Translucent marker over an area. |
| Blur | B | Pixelates anything private. |
| Text | T | Click and type. Return finishes, Option-Return adds a line. |
| Crop | C | Drag the area to keep. |
| Select | V | Move items, drag the dots to reshape, Delete removes, double-click text to edit. |

Picking a color or moving **Size** restyles the selected item. Undo and redo cover everything, crop included. Hover over any button to see what it does; the description also appears in the bar at the bottom.

### Capture history

The strip under the image shows your recent captures, newest first, like Snagit's tray. Click one to open it in the same window (unsaved markup on the current one is saved first). If a capture has a marked-up copy, that's what you see. Right-click a thumbnail for Open in New Window, Open Original (without markup), Copy Image, Show in Finder, or Move to Trash. Hide or show the strip with ⇧⌘H.

### Sending it

- **⌘C** copies the marked-up image. **⌘Return** copies it and closes the editor.
- Drag the **Drag** box into Mail, Slack, Messages or a Finder folder.
- **⌘S** saves to `~/Pictures/Mac Capture Studio`. Every capture is also kept there, and closing an editor with unsaved markup saves a “marked up” copy instead of discarding it.

### Menu bar options

Capture in 3 seconds (for open menus), New from Clipboard, Open Image…, Show Captures Folder, Capture Shortcut, Open at Login, and How to Use.

### Choosing your own shortcut

Menu bar icon › Capture Shortcut › **Choose Your Own Shortcut…**, then press the keys you want. Any one modifier (⌃, ⌥ or ⌘) plus one key works, so two-key shortcuts like ⌃\` or ⌃1 are fine, as is a function key like F13 on its own. The window tells you if a shortcut is already taken or would break something (⌘C, ⌘Q, the macOS screenshot keys and so on). Quick presets: ⇧⌘2, ⌃\`, ⌃1, ⌃⇧S, F13.

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
- `Source/Shortcut.swift`: hotkey storage and the Choose Your Own Shortcut window.
- `Source/History.swift`: the capture history strip and image loading.
- `Tools/MakeIcon.swift`: draws the app icon at build time.

The original Electron prototype is in git history (before the `claude/native-step-capture` branch).
