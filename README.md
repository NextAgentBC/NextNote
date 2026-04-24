# NextNote

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
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

## Quick start

```sh
brew install xcodegen            # one-time
# optional (enables YouTube downloads):
brew install yt-dlp ffmpeg

git clone https://github.com/<you>/nextNote.git
cd nextNote
make build                       # xcodegen + xcodebuild + ad-hoc sign
make run                         # launch nextNote.app
```

First launch: pick (or accept defaults for) three folders — Notes, Media, Ebooks — under `~/Documents/nextNote/`. Everything else is configured from **Settings** and **Library** menu.

## Features

- **Notes.** Plain `.md` files on disk, folder tree in the sidebar, Markdown editor with split preview, search, tabs, focus mode, per-note chat, dashboard, daily digest.
- **Ebooks.** `.epub` reader inline: TOC, page turn (click edge / arrows / space), highlights, fonts, themes. Auto-scanned from the Ebooks root.
- **Media.** Music and video auto-scanned from the Media root. Click a track → `AmbientPlayer` starts; click a video → inline `MediaPlayerView`.
- **AI.** Polish / summarize / translate / grammar / continue writing. Swap providers in Settings — MLX on-device, remote OpenAI-compatible (Ollama, vLLM, LM Studio, any HTTP endpoint), or Google Gemini (free tier with automatic key rotation).
- **YouTube.** Paste URL → `yt-dlp` downloads to the Media folder (mp3 / mp4). Needs `yt-dlp` installed; `ffmpeg` unlocks mp3 + ≥1080p video.

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

v0.1. Features listed above are working. Test target not added yet — high-value candidates are in [TUTORIAL.md](TUTORIAL.md#12-contributing).

## License

Not yet set — pick MIT or Apache-2.0 before publishing.
