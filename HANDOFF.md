# Handoff

## Latest session
- **AI:** Claude Opus 5.5
- **Mac:** MacBook Pro Work
- **Date:** 2026-11-16
- **Branch:** claude/hotkey-recorder-and-step-moving (not merged to main yet)
- **What changed:** "Choose Your Own Shortcut…" recorder (Source/Shortcut.swift) accepts any single modifier + key or a lone F-key, and blocks or warns on risky combos. The step tool now grabs and moves an existing number instead of stacking a new one. Every toolbar control has a plain-English tooltip, and the same text shows instantly in the bottom bar on hover. The blur icon is now an eye with a slash. Added a Snagit-style capture history strip under the image (Source/History.swift): click to swap a capture into the window, right-click for more, ⇧⌘H toggles it.
- **What works / was tested:** Builds with no warnings. A scripted test covered: clicking a step selects it without adding one, dragging moves it, undo restores it, and clicking empty space adds the next number. It also covered history grouping (original + marked up) and swapping captures in the window, which auto-saves dirty markup as "… marked up.png". Installed to /Applications.
- **Not yet verified:** The shortcut recorder window and hover text in the live app (needs Sam). A rebuild can make macOS ask for Screen Recording permission again.
- **Next steps:** Sam tries it. If good, merge to main. Then continue ROADMAP "Next up".
- **Open questions for Sam:** None.
