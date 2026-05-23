# NextNote

[![License: PolyForm NC 1.0](https://img.shields.io/badge/license-PolyForm_NC_1.0-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift 6.0](https://img.shields.io/badge/swift-6.0-orange.svg)](https://swift.org)
[![Release](https://img.shields.io/github/v/release/NextAgentBC/NextNote?include_prereleases)](https://github.com/NextAgentBC/NextNote/releases)
[![Stars](https://img.shields.io/github/stars/NextAgentBC/NextNote?style=social)](https://github.com/NextAgentBC/NextNote)

Local-first macOS app for Markdown notes, EPUB reading, and media playback. Three separate on-disk roots (Notes / Media / Ebooks), multi-provider AI (on-device MLX + remote OpenAI-compatible + Gemini), optional YouTube downloads via `yt-dlp`. No account, no telemetry. macOS 14+.

- End-user docs → **[USER_GUIDE.md](USER_GUIDE.md)**
- Contributor / architecture reference → **[TUTORIAL.md](TUTORIAL.md)**
- LLM provider setup → **[docs/LLM_SETUP.md](docs/LLM_SETUP.md)**
- Release process → **[RELEASE.md](RELEASE.md)**
- Known rough edges + UX roadmap → **[UX_AUDIT.md](UX_AUDIT.md)**
- Changelog → **[CHANGELOG.md](CHANGELOG.md)**

## Download

Grab the latest signed + notarized `.dmg` from the **[Releases page](https://github.com/NextAgentBC/NextNote/releases/latest)** — drag it into `/Applications` and double-click. No Gatekeeper warnings: the app is Developer ID–signed and Apple-notarized. macOS 14+.

## Quick start

```sh
brew install xcodegen            # one-time
# optional (enables YouTube downloads):
brew install yt-dlp ffmpeg

git clone https://github.com/NextAgentBC/NextNote.git
cd NextNote
make build                       # xcodegen + xcodebuild + ad-hoc sign
make run                         # launch nextNote.app
```

First launch: pick (or accept defaults for) three folders — Notes, Media, Ebooks — under `~/Documents/nextNote/`. Everything else is configured from **Settings** and **Library** menu.

## Features

- **Notes.** Plain `.md` files on disk, folder tree in the sidebar, Markdown editor with split preview, search, tabs, focus mode, per-note chat, dashboard, daily digest.
- **Wiki-links.** `[[Note]]` and `[[Note|alias]]` syntax in markdown — preview renders them as clickable pills. Click → opens the target note, or creates it at the vault root if missing.
- **Backlinks.** Status bar pill shows the count of notes that link to the active note via `[[…]]`. Click to expand a list of source notes; click a source to jump there. Index auto-rebuilds in the background on every vault edit.
- **Tags.** Inline `#tag` plus YAML frontmatter `tags: [...]` are indexed across the vault. **Workflow → Browse Tags…** (⌥⌘T) opens a two-pane browser: tags + counts on the left, notes for the selected tag on the right.
- **Quick switcher.** ⌘P opens a fuzzy-find palette over every note in the vault (exact / prefix / contains / subsequence scoring). Empty query shows your most-recent files first.
- **Recent files.** `File → Open Recent` keeps the last 30 opens across launches, auto-pruned on rename / delete.
- **Pinned folders.** `Library → Open Folder in Sidebar…` (⇧⌘O) — pick any folder anywhere on disk and pin it to the sidebar with a security-scoped bookmark. Browse + open files without making them part of the Notes vault.
- **Daily note.** ⇧⌘D opens or creates `<vault>/Daily/YYYY-MM-DD.md` with a date heading.
- **Frontmatter titles.** `title: My Better Title` in YAML frontmatter overrides the on-disk filename in tabs, recents, and quick switcher.
- **AI summarize.** ⌥⌘S streams a 3-5 bullet summary of the active note. Uses the same provider stack as inline AI tools.
- **Tab jumps.** ⌘1…⌘8 jump straight to tab N; ⌘9 jumps to the last tab.
- **Reading time.** Status bar shows estimated reading time (200 wpm) + unsaved-changes dot.
- **Ebooks.** `.epub` reader inline: TOC, page turn (click edge / arrows / space), highlights, fonts, themes. Auto-scanned from the Ebooks root.
- **Media.** Music and video auto-scanned from the Media root. Click a track → `AmbientPlayer` starts; click a video → inline `MediaPlayerView`.
- **Drawing notes.** Handwriting / sketch notes (`.nndraw`) stored as re-editable JSON in the vault — ink strokes across multiple pages, each with an optional full-page background (an imported PDF page render or a pasted screenshot) plus free-floating placed images. Reopen and keep editing the raw strokes anytime.
- **PDF.** Inline PDF reader with outline TOC and page navigation; markup pages and send a page into a drawing note for annotation.
- **AI.** Polish / summarize / translate / grammar / continue writing. Swap providers in Settings — MLX on-device, remote OpenAI-compatible (Ollama, vLLM, LM Studio, any HTTP endpoint), or Google Gemini (free tier with automatic key rotation).
- **YouTube.** Paste URL → `yt-dlp` downloads to the Media folder (mp3 / mp4). Needs `yt-dlp` installed; `ffmpeg` unlocks mp3 + ≥1080p video.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘P | Quick switcher |
| ⇧⌘D | Daily note |
| ⇧⌘O | Open folder in sidebar |
| ⌘1…⌘8 | Jump to tab N (⌘9 = last) |
| ⌥⌘S | AI summarize note |
| ⌥⌘T | Browse tags |
| ⌘⇧K | AI terminal |
| ⌘⇧T | Show shell |
| ⌘⇧P | Floating preview |
| ⌘/ | Shortcuts overlay |

## Build targets

```sh
make gen      # regenerate nextNote.xcodeproj via xcodegen
make build    # Debug build + ad-hoc code sign (survives iCloud xattrs)
make run      # build + launch
make clean    # nuke generated project + build output
```

Build artifacts live in `build.nosync/` — the `.nosync` suffix keeps iCloud Documents from syncing a multi-GB bundle.

## Project shape

```
nextNote/
├── Makefile                 build targets
├── project.yml              xcodegen config
├── TUTORIAL.md              full reference for contributors
├── nextNote/
│   ├── nextNoteApp.swift    @main; scene + env object wiring
│   ├── Models/              data types + SwiftData @Models
│   ├── Services/            business logic
│   │   ├── AI/              LLMProvider + MLX / remote / Gemini impls
│   │   ├── Audio/           AmbientPlayer + legacy MediaLibrary
│   │   ├── Chat/            per-note chat sessions
│   │   ├── Dashboard/       pinned notes + AI rollup view service
│   │   ├── Digest/          daily digest rollups
│   │   ├── Download/        yt-dlp locator + downloader + search
│   │   ├── EPUB/            parser + importer + book-library scanner
│   │   ├── Media/           MediaCatalog (music + video scan for sidebar)
│   │   ├── Security/        Keychain
│   │   └── Vault/           LibraryRoots + VaultStore + NoteIO
│   ├── Views/               SwiftUI — grouped by feature
│   ├── Utilities/           menu commands
│   └── Resources/           Info.plist, Assets.xcassets
└── build.nosync/            generated
```

## Dependencies

All pulled via SwiftPM (see `project.yml`):

- [`mlx-swift-lm`](https://github.com/DePasqualeOrg/mlx-swift-lm) — MLXLLM + MLXVLM
- [`swift-tokenizers-mlx`](https://github.com/DePasqualeOrg/swift-tokenizers-mlx)
- [`swift-hf-api-mlx`](https://github.com/DePasqualeOrg/swift-hf-api-mlx)
- [`ZIPFoundation`](https://github.com/weichsel/ZIPFoundation) — EPUB unzip
- [`SwiftSoup`](https://github.com/scinfu/SwiftSoup) — OPF / NCX / nav parsing

Apple platform frameworks only beyond those.

## Status

v0.4.0 — signed & notarized `.dmg` on the [Releases page](https://github.com/NextAgentBC/NextNote/releases/latest). Features listed above are working. Test target not added yet — high-value candidates are in [TUTORIAL.md](TUTORIAL.md#12-contributing).

## License

[PolyForm Noncommercial License 1.0.0](LICENSE) — source-available, free for personal / research / nonprofit / educational use. **Commercial use is not granted.** For a commercial license, contact NextAgentBC via GitHub. See also [NOTICE](NOTICE).

Note: PolyForm Noncommercial is a *source-available* license, not an OSI-approved open-source license — the OSI definition prohibits field-of-use restrictions, and "noncommercial only" is one. The source is public, forkable, and modifiable for any noncommercial purpose.
