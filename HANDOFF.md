# Handoff

## Latest session
- **AI:** Claude Opus 5.5
- **Mac:** MacBook Pro Travel
- **Date:** 2026-11-18
- **Branch:** main
- **What changed:** No code changes. This was cleanup and a sync of the Travel Mac. The Travel Mac was still on the old Electron branch, so it was switched to main, pulled, and the Swift app was built and installed with `./build.sh --install`. The repo is now down to the `main` branch only. Deleted from GitHub and locally: `claude/region-capture-steps` (the abandoned Electron prototype, never merged) and the two merged Swift branches, `claude/native-step-capture` and `claude/hotkey-recorder-and-step-moving`. Also deleted the Travel Mac's leftover Electron `node_modules` (272 MB, untracked) and the stash of unused Electron 45 upgrade edits. The `v1.0` tag is unchanged.
- **What works / was tested:** The universal build (arm64 + x86_64) builds cleanly on the Travel Mac. It's installed in /Applications and launches.
- **Not yet verified:** A real capture on the Travel Mac, since macOS may ask for Screen Recording permission first. Still unchecked in the live app from the 2026-11-16 Work Mac session: the shortcut recorder window, hover text, auto-copy after a real capture, and the right-click menu.
- **Next steps:** Continue ROADMAP "Next up" (step captions and legend next). Both Macs are now on main and running the same Swift app.
- **Open questions for Sam:** None.
