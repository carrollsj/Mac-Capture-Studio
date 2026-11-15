# Mac Capture Studio

A Snagit-inspired macOS capture and markup app. It supports screen/window capture, drawing and annotation tools, undo/redo, export/copy, and editable hotkeys.

## Run on a Mac

1. Install Node.js from <https://nodejs.org/> if `npm` is not available.
2. In this folder, run:

```bash
npm install
npm start
```

On first capture, macOS may ask for Screen Recording permission. Enable it in System Settings, then restart the app.

## Browser fallback

You can also open `src/index.html` directly in Chrome, Edge, or Safari. Capture and markup work, but global hotkeys only work while the page is focused.

## Features

- Capture screen, window, or tab using the native picker
- Markup tools: select, pen, highlighter, arrow, line, rectangle, ellipse, text, pixelate blur, crop
- Change color and stroke width
- Undo, redo, clear markup, reset image
- Export PNG, copy PNG to clipboard, save/load project JSON
- Configurable hotkeys saved locally
- Electron global hotkeys for capture/open editor/quick export when running as the desktop app

This is not a clone of TechSmith Snagit internals or proprietary workflows. It is a clean-room capture and markup app with a similar practical feature set.
