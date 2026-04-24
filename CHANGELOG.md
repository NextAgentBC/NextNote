# Changelog

## 0.1.0 — 2026-04-23

Initial public release.

### Features

- **Notes** — plain `.md` on disk, folder tree, split preview with KaTeX math, search, tabs, focus mode, auto-save.
- **Ebooks** — inline EPUB reader with TOC, paging (click edges / ←/→ / space), highlights, font + theme. Books grouped by sub-folder in the sidebar.
- **Media** — music + video auto-scan from the Media root, grouped by folder, click to play in the ambient bar. Drag-to-merge sibling folders (e.g. "GEM 邓紫棋" onto "邓紫棋").
- **AI** — pluggable `LLMProvider`: on-device MLX (free, Apple Silicon), any OpenAI-compatible endpoint (Ollama / vLLM / LM Studio), or Google Gemini free tier with key rotation. Polish / summarize / continue / translate / grammar / per-note chat / daily digest.
- **YouTube** — paste URL → `yt-dlp` downloads to the Media folder. Auto-classify into artist folders with AI canonicalization (G.E.M. → 邓紫棋).
- **Tabs** — books, notes, and media all share one tab bar. Multiple books open at once.
- **Three independent library roots** — Notes, Media, Ebooks — each its own security-scoped bookmark, defaults under `~/Documents/nextNote/`, changeable anytime via the Library menu.
- **Auto-rescan** — refreshes on window focus + every 15 s while focused.

### Docs

- `README.md` — quick start
- `USER_GUIDE.md` — end-user walkthrough
- `TUTORIAL.md` — architecture + every service file
- `RELEASE.md` — how to cut a release
- `UX_AUDIT.md` — known rough edges + roadmap
- `docs/LLM_SETUP.md` — provider-specific AI configuration
- `demo/` — sample EPUB (Alice in Wonderland, PD), sample MP4 (Big Buck Bunny, CC BY), starter notes

### Build

```sh
brew install xcodegen
make build      # Debug
make release    # dist/nextNote-0.1.0.{zip,dmg}
```
