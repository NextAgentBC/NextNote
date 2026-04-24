# Changelog

## 0.1.2 — 2026-04-24

### Features

- **Asset Library (素材库)** — dedicated 4th library root for visual scratch material. Adds a new sheet (Media ▸ Asset Library, ⌘⇧A) that shows every image / video / audio file under the Assets root in a grid of thumbnails, with a kind filter (All / Images / Videos / Audio) and live search.
  - **Drag-and-drop import** — drop files from Finder anywhere in the grid to copy them into the Assets folder (duplicates get `-2`, `-3`, … suffixes).
  - **Drag-to-embed** — drag any asset cell into a Markdown note and the editor inserts `![title](path)`; the preview renders images as `<img>`, video as `<video controls>`, and audio as `<audio controls>` automatically (extension-based, handled by the existing preview embed machinery).
  - **Preview** — double-click any cell to open a full-size preview. Video assets get the existing Trim editor (scissors button in the player toolbar); audio gets inline playback.
  - **Thumbnails** — real image thumbnails for stills; video thumbnails are grabbed via `AVAssetImageGenerator` at ~0.5 s (skips black intro frames). Audio falls back to the waveform SF Symbol.
  - **Right-click menu** — Preview, Reveal in Finder, Copy Markdown Embed, Move to Trash.
  - **Graceful adoption** — the Assets root is optional; it auto-creates `~/Documents/nextNote/Assets/` on first open, so existing 0.1.1 installs don't see a re-setup prompt.
- **Image support in the editor drop handler** — dropping a video or audio file from Finder onto a note now inserts the same `![](…)` syntax the preview already knew how to render (previously limited to image extensions).

## 0.1.1 — 2026-04-24

### Fixes

- **YouTube video playback — silent 4K / 1440p downloads.** YouTube only ships H.264 up to 1080p; higher tiers come as VP9 or AV1, which AVPlayer can't decode on older macOS or Intel Macs, so the picture went blank while audio still played. After a successful download, the file is now probed and — if the video track is VP9 / AV1 — re-encoded in place to HEVC (`hvc1`) via VideoToolbox hardware encode. H.264 / HEVC downloads pass through unchanged.
- **Media sidebar didn't refresh after a YouTube download.** New files landed on disk but the left sidebar's folder tree only re-scanned on window focus / every 15 s, so a fresh download stayed invisible until the user clicked away and back. Downloads now trigger an immediate catalog rescan.
- **Auto-classified downloads landed outside the Media library root.** When the yt-dlp download folder and the Media library root differed (common setup: yt-dlp writes to `~/Downloads/yt`, Media root is `~/Downloads/yt/Music`), the AI classifier created `<Artist>/` subfolders next to the library root instead of inside it — so the files never showed up in the left sidebar. Classification now targets the Media library root directly.
- **ffmpeg hang on post-download transcode.** The transcoder launched ffmpeg without `-nostdin`, so it stalled at ffmpeg's interactive prompt. Both the in-app transcoder and `scripts/repair-videos.sh` now pass `-nostdin`.

### Features

- **Media sidebar right-click menu.**
  - Right-click a folder group → **Play All**, **Play Shuffled**, **Enqueue**, **Reveal in Finder**.
  - Right-click a single file → **Play**, **Enqueue**, **Reveal in Finder**.
  - Any video in the queue automatically pops the Video Vibe window.
- **`scripts/repair-videos.sh`** — batch-repair VP9 / AV1 files already on disk from 0.1.0 downloads. Usage: `scripts/repair-videos.sh <folder> [--dry-run]`. Re-encodes only the files that need it; leaves H.264 / HEVC alone.

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
