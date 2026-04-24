# Changelog

## 0.3.0 — 2026-04-24

### AI Soul — Phase C begins

Day-to-day ergonomics for the CLI-first workflow shipped in 0.2.0.

- **Open Today's Daily Note** (⌘⇧D) — materializes `10_Daily/YYYY-MM-DD.md` from `99_System/Templates/Daily_Note.md` if missing, opens as a tab. Falls back to a minimal skeleton when the preset isn't seeded.
- **Quick Capture HUD** (⌘⇧N) — floating overlay with a textarea + destination picker (Swipe / Inbox / Ingest). Auto-pastes a URL or long-selection from the clipboard on open. Composes the right slash command and fires it through the embedded terminal — the skill owns file writes.
- **Apply AI Soul Preset** manual item under the Library menu — re-seed or update an existing vault without re-running first-launch setup. Idempotent; never overwrites user edits.
- **AI menu**: now carries 4 entries (Run Skill, Show Terminal, Open Daily Note, Quick Capture) with their accelerators.

## 0.2.0 — 2026-04-24

### AI Soul — Phase A + B shipped

First major leap toward the [AI_PLAN.md](AI_PLAN.md) vision: nextNote becomes a first-class host for **Claude Code / Gemini CLI** workflows, with the vault as the single source of truth for identity, memory, and skills.

**Phase A — vault template + preset seeder**
- New **"Use AI Soul preset"** checkbox in first-run Library setup. On start, copies a full opinionated vault template into the Notes root (idempotent; never overwrites user edits).
- Template fuses four methodologies: OrbitOS workflow folders, Karpathy LLM wiki compounding (`80_Raw/` → `40_Wiki/`), Soul/auto-memory (Soul.md + typed memory files), and Dan Koe weekly canvas + swipe file.
- Ships **21 slash-skills** under `99_System/.claude/skills/`:
  - knowledge: `ingest`, `query`, `lint`, `parse-knowledge`
  - creator: `weekly-canvas`, `swipe-save`, `coach`, `brand-strategy`, `content-engine`, `offer-builder`, `publish-ready`
  - daily: `start-my-day`, `kickoff`, `research`, `archive`, `ask`, `brainstorm`
  - digest: `ai-newsletters`, `ai-products`
  - hygiene: `consolidate-memory`, `raw-gc` — hard budgets (200-line MEMORY.md, 2 GB `80_Raw/`, 90-day TTL) with `_trash/YYYY-MM-DD/` staging for 30-day recovery
- 6 markdown templates (Daily / Project / Wiki / Inbox / Canvas / Raw) + 2 seed personas (SE_Architect, General_FirstPrinciples).

**Phase B — embedded terminal + command palette**
- **Embedded terminal** (⌘⇧T) via [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm). Docks below the editor; shell cwd auto-pins to the vault's Notes root so slash-skills resolve relative paths. Persists open/closed across launches.
- **Command palette** (⌘K): scans `99_System/.claude/skills/*/SKILL.md` from the active vault, fuzzy-ranks by query, arrow-key navigable. Enter runs `claude "/<skill>"` in the terminal and auto-opens the pane.
- New **AI menu** in the menubar surfaces both shortcuts alongside their keyboard accelerators.

**Notes**
- 0.1.x AI stack (MLX / AIChatPanel / AITextService) is untouched — still shippable. Phase D will prune it.
- Works with vanilla Claude Code or Gemini CLI — no custom AI code added to nextNote itself.

## 0.1.4 — 2026-04-24

### License change

- **Relicensed from Apache 2.0 → PolyForm Noncommercial 1.0.0.** NextNote is now source-available (not OSI "open source"): free for personal / research / nonprofit / educational use, commercial use requires a separate license from NextAgentBC. LICENSE, NOTICE, README, TUTORIAL, USER_GUIDE, RELEASE, Makefile, Info.plist, and project.yml copyright strings all updated.

### Media — unified sidebar + popup

- **One source of truth.** Sidebar Media tray and Media Library popup now read from the same persisted store (`MediaLibrary`). Renames, removes, and adds in the popup show up live in the sidebar (and vice versa); the stale dual-catalog design is gone.
- **`MediaLibrary.scanRoot(_:)`** — ingests every audio/video file under the vault's Media root, prunes entries whose files vanished, dedupes by path.
- **Track-level context menu in sidebar.** Right-click a media row → Play / Enqueue / Add to Assets / Reveal in Finder / Remove from Library / Move to Trash.
- **AmbientBar cleanup.** Dropped the redundant "Media Library" button from the ambient player bar — the sidebar is now the canonical browsing UI. Popup is still reachable via ⌘⇧M for playlists, Auto-Clean, and Restore Titles admin.
- Deleted `MediaCatalog.swift` (dead after consolidation).

## 0.1.3 — 2026-04-24

### Asset Library — folders, categories, UX pass

- **Default category folders** (`images / videos / audio / docs / other`). The Assets root is auto-populated with these subfolders the first time it's opened; the Asset Library left pane always lists the five built-ins even when empty, so new users see the layout up front.
- **Custom folders.** "New Folder" button in the Asset Library creates an arbitrary subfolder alongside the built-ins. Folder name is path-sanitized (`/` and `:` stripped).
- **Folder sidebar** (left pane of the Asset Library sheet). "All" + "Loose" + one row per first-level subfolder, each with its own count badge. Clicking filters the grid. Dragging an asset cell onto a folder row **moves** the file into that folder.
- **Auto-routing on import.** Finder drops, YouTube "Save to Assets", clipboard paste, and sidebar-tray drops now land in the kind-matching subfolder instead of the root — so an image pastes into `images/`, a YouTube video lands in `videos/`, etc. Importing while a specific folder is selected drops into that folder instead.
- **Single-click preview.** Clicking a cell opens the preview sheet directly (videos get the existing Trim editor). Previously required a double-click. Drag still works — SwiftUI gives drag-gesture priority.
- **Right-click "Move to…"** on asset cells, populated from the full folder list.

### Sidebar toolbar

- **New Note + New Folder merged into a single "+" menu** so neither action hides in the SwiftUI overflow chevron on narrow window widths.

### Asset Library thumbnails

- **Non-black video frames.** `AVAssetImageGenerator` used to sample only at 0.5 s, which often returned a pure-black fade-in frame for YouTube music videos and trailers. The generator now tries 10 % of duration / 5 s / 2 s / 0.5 s, downsamples each candidate to 16×16 grayscale, and keeps the first non-black frame. Falls back to whatever it got if everything is dark.

### YouTube download UX

- **"Save to Media / Assets" segmented picker.** Pointing a download at Assets routes it into `videos/` or `audio/` under the Assets root, skipping the AI artist classifier.
- **Auto-adopt `yt-dlp` / `ffmpeg`** when they're installed at their standard Homebrew paths. The sheet now shows a green checkmark + path when a tool is present, and a copyable `brew install …` hint otherwise. The forced `Choose…` click every fresh install is gone. (Sandbox is now off; see note below.)

### App-wide

- **Sandbox disabled.** nextNote now runs outside the macOS App Sandbox so it can spawn user-installed CLI tools (yt-dlp, ffmpeg, ollama) from fixed Homebrew paths without making the user re-grant every binary via NSOpenPanel on each fresh install. Hardened runtime + notarization still apply; the app still ships signed + notarized in the released DMG.
- **Asset Library header two-row layout** — title + actions on top, filter + search below — so the sheet stays usable at its 860×560 minimum size.
- **Clipboard paste (⌘V) in the Asset Library** saves the clipboard image (screenshots, Preview copy, browser "Copy Image") as `pasted-YYYY-MM-DD-HHMMSS.png` in `images/`.
- **Drag Media sidebar rows → Assets tray** to copy a music/video file into the Asset Library's matching subfolder. The Media row context menu gains "Add to Assets" as a click-only alternative.

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
