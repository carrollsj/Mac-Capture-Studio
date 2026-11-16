# Handoff

## Latest session
- **AI:** Claude Opus 5.5
- **Mac:** MacBook Pro Work
- **Date:** 2026-11-16
- **Branch:** claude/native-step-capture (not merged to main yet)
- **What changed:** Replaced the Electron prototype with a native Swift menu bar app (Source/*.swift, build.sh). Global hotkey ⇧⌘2 runs the system area/window picker and opens the capture in an editor. Tools: numbered steps (auto-increment; drag adds a pointer; type 1–9 to restart), arrow, box, circle, highlight, blur, text, crop, select/move/reshape. Copy (⌘C), copy and close (⌘Return), drag-out, save to ~/Pictures/Mac Capture Studio. Installed to /Applications.
- **What works / was tested:** Builds universal (arm64 + x86_64) with no warnings. A scripted test drove the real canvas with simulated clicks and drags: step numbering, pointer tails, restart numbering, all tools, move, delete/undo, crop/undo and full-resolution Retina export. The PNGs were checked by eye. The app launches from /Applications.
- **Not yet verified:** A live hotkey capture (needs Sam to grant Screen Recording; Claude's shell can't take screenshots), typing in the text tool, drag-out, and Open at Login.
- **Next steps:** Sam tries a real capture. If it works, merge to main. See ROADMAP.md.
- **Open questions for Sam:** Is ⇧⌘2 a good default hotkey?
