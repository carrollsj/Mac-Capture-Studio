# Mac-Capture-Studio — instructions for every AI

This file is the single source of truth for any AI working in this repo (Claude, ChatGPT/Codex, Muse, or anything else).
Tool-specific files such as `CLAUDE.md` only point back here.

## What this project is
Native macOS (Swift/AppKit) menu bar screenshot and markup app: hotkey capture that opens straight into an editor with numbered steps, arrows, boxes, highlight, blur, text and crop, then copy/drag/save.

## Ground rules
- **Work from `ROADMAP.md`:** do the first unchecked item under "Next up" unless Sam asks for something else. Check it off (`- [x]`) and move it to "Done" when it is finished and tested.
- GitHub (`origin`) holds the master copy. Pull before you start, and commit and push before you stop.
- Work on a branch named for your AI: `claude/<topic>`, `codex/<topic>`, `muse/<topic>` and so on. Merge to `main` only when it builds and works.
- Never commit secrets (`.env`, API keys, passwords) or build output. `.gitignore` already covers the usual ones.
- Keep code changes small and focused, and explain *why* in commit messages.

## Every commit message ends with these two lines
```
AI: <your name and model, e.g. Claude Opus 5.5 / ChatGPT Codex / Muse>
Machine: <output of `scutil --get ComputerName`>
```
Sam uses these to see which AI and which Mac made each change.

## Before you finish a session
Update `HANDOFF.md` (overwrite the "Latest session" section), then commit and push it, so the next AI or Mac can pick up cold.

## How to build and run
- `./build.sh` builds `build.noindex/Mac Capture Studio.app` (the `.noindex` keeps it out of Spotlight/Launchpad). `./build.sh --install` copies it to /Applications and opens it.
- Only Xcode / Command Line Tools are needed. No packages.

## Project-specific notes
- **This repo is public** (made public 2026-11-16 so Sam can share download links). Keep secrets and personal details out of commits, notes and release text.
- New versions: bump CFBundleShortVersionString in Resources/Info.plist, run ./build.sh, zip the app with `ditto -c -k --keepParent`, and attach it to a GitHub release.
- Rewritten from Electron to native Swift on 2026-11-16 because the Mac had no Node and Sam wanted a hotkey that is always available. The Electron prototype is in git history.
- Builds are signed ad hoc, so macOS can ask for Screen Recording permission again after each rebuild.
- All drawing lives in `Renderer` (Model.swift) and runs in a flipped context, so the screen and the exported PNG use the same code.
