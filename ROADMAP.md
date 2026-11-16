# Mac-Capture-Studio roadmap

**Stage:** 🛠 In daily use (testing)
**What it is:** Native macOS screenshot and markup app for quick step-by-step how-to images.

## Finish line
A polished capture tool Sam uses daily: hotkey → markup with numbered steps → copy/send in seconds.

## Next up (work top to bottom; check items off as they're done)
- [ ] Sam: use it for real for a few days; note anything slow or missing
- [ ] Step captions + automatic legend
- [ ] Spotlight (dim everything except an area)
- [ ] Magnifier callout
- [ ] Guide mode: several captures combined into one image or PDF
- [ ] Keep markup editable after saving
- [ ] Include the pointer and click markers
- [ ] Sharing polish: border/shadow/padding, smaller-for-email export
- [ ] Copy text from a capture (OCR) and smart redact

## Later (after the finish line)
- Nothing planned yet.

## Done
- Moved to GitHub and ~/Developer; shared AI files added (2026-11-15)
- Ran it: Electron couldn't run (no Node on this Mac); decided to keep and rebuild natively (2026-11-16)
- Native rewrite: menu bar app, ⇧⌘2 global hotkey, editor with step numbers (auto-increment, pointer tails), arrow, box, circle, highlight, blur, text, crop, undo/redo, copy, drag-out, save (2026-11-16)
- Sam confirmed live hotkey capture works; merged to main (2026-11-16)
- Choose-your-own capture shortcut (any modifier + key, or an F-key); step tool can grab and move existing numbers; hover descriptions on every button; Snagit-style capture history strip (2026-11-16)
- Steps renumber on delete, can be renumbered by typing or right-click, and insert when the number exists; captures auto-copy to the clipboard, with an option to keep it updated while marking up (2026-11-16)
