# Handoff

## Latest session
- **AI:** Claude Opus 5.5
- **Mac:** MacBook Pro Work
- **Date:** 2026-11-16
- **Branch:** main (claude/hotkey-recorder-and-step-moving merged after Sam approved it)
- **What changed:** "Choose Your Own Shortcut…" recorder (Source/Shortcut.swift) accepts any single modifier + key or a lone F-key, and blocks or warns on risky combos. The step tool now grabs and moves an existing number instead of stacking a new one. Every toolbar control has a plain-English tooltip, and the same text shows instantly in the bottom bar on hover. The blur icon is now an eye with a slash. Added a Snagit-style capture history strip under the image (Source/History.swift): click to swap a capture into the window, right-click for more, ⇧⌘H toggles it. Steps now keep their order: delete closes the gap, a selected step can be renumbered by typing (one or two digits, one undo step) or via right-click, and placing an existing number inserts it. Each capture is copied to the clipboard on capture (on by default), and there's an optional setting to keep the clipboard updated while marking up. The menu bar menu now starts with Open Editor (newest capture, or brings an open editor forward; ⌘E) and a Recent Captures submenu. Reopening the app from Finder or Spotlight opens the editor.
- **What works / was tested:** Builds with no warnings. A scripted test covered: clicking a step selects it without adding one, dragging moves it, undo restores it, and clicking empty space adds the next number. It also covered history grouping (original + marked up) and swapping captures in the window, which auto-saves dirty markup as "… marked up.png". Step renumbering covered: delete, type-to-renumber, two-digit typing, insert, and the right-click menu. Installed to /Applications.
- **Not yet verified:** In the live app: the shortcut recorder window, hover text, auto-copy after a real capture, and the right-click menu (needs Sam). A rebuild can make macOS ask for Screen Recording permission again.
- **Next steps:** Continue ROADMAP "Next up" (step captions and legend next). Other Macs: pull, then run ./build.sh --install.
- **Open questions for Sam:** None.
