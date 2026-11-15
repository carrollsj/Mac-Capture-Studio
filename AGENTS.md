# Mac-Capture-Studio — instructions for every AI

This file is the single source of truth for any AI working in this repo (Claude, ChatGPT/Codex, Muse, or anything else).
Tool-specific files such as `CLAUDE.md` only point back here.

## What this project is
Snagit-style macOS screen capture and markup app (Electron): capture, annotate, blur, crop, export.

## Ground rules
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
- `npm install` then `npm start`.
- Browser fallback: open `src/index.html`.

## Project-specific notes
- None yet.
