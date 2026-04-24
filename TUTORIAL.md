# nextNote — Complete Tutorial & Reference

A macOS-native, local-first note, library, and media app. SwiftUI + SwiftData. Markdown notes, EPUB reader with highlights, inline music/video, multi-provider AI (on-device MLX + remote OpenAI-compatible + Gemini), YouTube download, per-note chat, daily digest.

Open-source friendly: no telemetry, no cloud account, user data lives on disk as plain files.

---

## 1. Project Overview

### What it does

| Pillar | Feature |
|---|---|
| **Notes** | Plain `.md` files on disk. Markdown editor with split preview. Search, tabs, per-note chat, dashboard, daily digest. |
| **Ebooks** | Open `.epub` inline. TOC navigation, chapter paging, highlights, font / theme. |
| **Media** | Auto-scan music + video folders. Click to play; ambient player persists queue. |
| **AI** | Polish / summarize / translate / grammar check / continue writing. On-device (MLX) or remote (Ollama, vLLM, OpenAI-compatible, Gemini). |
| **YouTube** | Paste URL → yt-dlp download → lands in your Media folder as mp3 / mp4. |

### Design principles

- **Local-first, file-first.** Notes are plain Markdown on disk. No proprietary database.
- **Three separate roots.** Notes / Media / Ebooks each live in their own folder, configured at first launch.
- **Provider-agnostic AI.** Swap MLX ↔ remote via Settings; same feature set.
- **Zero telemetry, zero account.**
- **Sandboxed**, security-scoped bookmarks for each chosen folder.

### Platform

- **macOS 14.0+** (Sonoma or later).
- Apple Silicon strongly preferred (MLX on-device models require it).
- Swift 6.0 / Xcode 16.0+.

---

## 2. Prerequisites

### Required

- **macOS 14+** on Apple Silicon (Intel works for everything *except* MLX on-device models).
- **Xcode 16+** (includes the Swift 6 compiler and macOS 14 SDK).
- **xcodegen** — project file generator:
  ```sh
  brew install xcodegen
  ```

### Optional — enable specific features

| Feature | Tool | Install |
|---|---|---|
| YouTube downloads | `yt-dlp` | `brew install yt-dlp` |
| High-quality video + MP3 conversion | `ffmpeg` | `brew install ffmpeg` |
| Import PDF / DOCX / XLSX / PPTX as markdown (planned) | `markitdown` | `uv tool install markitdown` (not wired up yet) |
| Remote AI provider | An OpenAI-compatible server (Ollama / vLLM / LM Studio) | See Ollama: `brew install ollama && ollama pull llama3.2` |
| Gemini AI | API key from [Google AI Studio](https://aistudio.google.com/) (free tier) | Paste key in Settings → AI |

If `yt-dlp` / `ffmpeg` aren't installed, the app still runs — YouTube download just stays disabled.

---

## 3. Build from Source

```sh
git clone https://github.com/<you>/nextNote.git
cd nextNote
brew install xcodegen     # one-time
make build                # generates project + builds Debug
make run                  # launches build.nosync/.../nextNote.app
```

The `Makefile` is small enough to read directly. Targets:

- `make gen` — regenerate `nextNote.xcodeproj` from `project.yml` via xcodegen.
- `make build` — xcodebuild Debug, emits unsigned app, ad-hoc signs it afterwards.
- `make run` — build + launch.
- `make clean` — remove generated project + build products.

Build output lives in `build.nosync/` — the `.nosync` suffix tells iCloud Documents to skip it, so a multi-GB artifact doesn't try to sync to CloudKit.

### Installing to `/Applications`

```sh
cp -R build.nosync/Build/Products/Debug/nextNote.app /Applications/
```

Gatekeeper may complain the first time (ad-hoc signature). Right-click → Open, or run:

```sh
xattr -dr com.apple.quarantine /Applications/nextNote.app
```

---

## 4. First-Run Setup

On first launch, the **Library Setup** screen appears. Pick (or accept defaults for) three folders:

```
📝 Notes    ~/Documents/nextNote/Notes
🎵 Media    ~/Documents/nextNote/Media
📚 Ebooks   ~/Documents/nextNote/Ebooks
```

Click **Use Defaults for All** + **Start** to create the three subfolders under `~/Documents/nextNote/`, or click **Change…** on any row to pick an existing folder (e.g. `~/Music` for Media).

Each folder is opened with a **security-scoped bookmark**, persisted to UserDefaults so sandbox access survives app launches. You can change any root later via the **Library** menu.

---

## 5. Menu Structure

| Menu | Contents |
|---|---|
| **File** | Save (⌘S), Open File… (⌘O), New Tab (⌘T), Close Tab (⌘W) |
| **Edit** | Find… (⌘F) |
| **View** | Toggle Sidebar (⌘1), Preview Mode picker, Enter Focus Mode (⌘⇧\\) |
| **Library** | Change Notes/Media/Ebooks Folder…, Reveal in Finder, Rescan Library (⌘R) |
| **Media** | Play / Pause (⌥Space), Next / Previous (⌘⌥←/→), Media Library (⌘⇧M), Video Vibe Window, Ambient Library Folder, Download from YouTube… |
| **AI** | Rebuild Dashboards (⌘⇧R), Run Daily Digest, Summarize (⌘⌥S), Polish, Continue, Translate, Grammar Check |

---

## 6. Architecture Map

```
nextNote/
├── Makefile                 build targets (xcodegen + xcodebuild)
├── project.yml              xcodegen config → generates nextNote.xcodeproj
├── nextNote/
│   ├── nextNoteApp.swift    @main; wires env objects + scenes
│   ├── Models/              data types + SwiftData @Models
│   ├── Services/            business logic, singletons, I/O
│   ├── Views/               SwiftUI view hierarchy
│   ├── Utilities/           menu commands, small helpers
│   └── Resources/           Info.plist, Assets.xcassets
└── build.nosync/            generated — ignored
```

### Key design rules

- `Services/` is platform-free SwiftUI-free logic. Views call into services; services never import SwiftUI types.
- `Models/` contains both plain value types and `@Model` classes (SwiftData).
- `Views/` groups by feature (`EPUB/`, `Sidebar/`, `Editor/` …) — not by widget type.
- A singleton is only used when the feature truly needs one process-wide instance (e.g. `AmbientPlayer.shared`, `AITextService.shared`). Everything else is injected via `@StateObject` / `@EnvironmentObject`.

### Scene & state graph

```
NextNoteApp (@main)
├── @StateObject appState        AppState            — tabs, flags, triggers
├── @StateObject vaultStore      VaultStore          — Notes file tree
├── @StateObject libraryRoots    LibraryRoots        — 3 root URLs + bookmarks
├── @StateObject mediaCatalog    MediaCatalog        — music + video scan
├── ModelContainer (SwiftData)   NextNoteSchemaV3    — books, notes index, chat, etc.
│
└── Scenes:
    ├── WindowGroup → ContentView     — main window, sidebar + detail
    ├── Settings    → SettingsView    — preferences
    └── (iOS)       → ContentView     — not shipped yet
```

---

## 7. Code Layout (~16 k lines of Swift)

### Models

| File | Purpose |
|---|---|
| `AppState.swift` | Transient UI state: open tabs, active book ID, focus mode, search text, one-shot triggers |
| `UserPreferences.swift` | `@AppStorage`-backed settings |
| `SchemaVersions.swift` | SwiftData versioned schemas (V1 → V2 → V3) |
| `TextDocument.swift` | Legacy flat-mode note model (kept for migration) |
| `Note.swift` | Vault-backed note index row (relative path, hash, AI summary cache) |
| `Book.swift` / `BookHighlight.swift` | EPUB library entries + inline highlights |
| `FolderNode.swift` | Recursive sidebar tree node |
| `FileType.swift` | Extension → display type (md, txt, epub, code, markup …) |
| `FileCategory.swift` | Extension → category bucket (`.note / .book / .music / .video / .image / .other`) |
| `MediaKind.swift` | audio / video buckets + extension sets |
| `Track.swift` | Playlist track (URL + security-scoped bookmark) |

### Services

#### `Services/Vault/`
| File | Purpose |
|---|---|
| `VaultStore.swift` | Scans Notes root into a `FolderNode` tree. CRUD via `NoteIO`. Single root; LibraryRoots owns the URL. |
| `LibraryRoots.swift` | Three independent roots (Notes / Media / Ebooks) + bookmark persistence + `pick(kind:)` + defaults. |
| `VaultBookmark.swift` | Legacy single-root bookmark (kept for migration). |
| `NoteIO.swift` | Atomic `.md` read / write, sanitized filenames, SHA256, trash-based delete. |

#### `Services/EPUB/`
| File | Purpose |
|---|---|
| `EPUBParser.swift` | ZIP unzip (ZIPFoundation) → container.xml → OPF → manifest/spine/NCX/nav parse (SwiftSoup). |
| `EPUBImporter.swift` | Import-copy or register-existing flows; hash dedupe; chapter → markdown export. |
| `BookLibrary.swift` | Walks `ebooksRoot/` and registers every `.epub` via `EPUBImporter.registerExisting`. |
| `XHTMLToMarkdown.swift` | DOM walker converting chapter XHTML into Markdown. |

#### `Services/Media/`
| File | Purpose |
|---|---|
| `MediaCatalog.swift` | Transient music / video list scanned from `mediaRoot`. Used by the sidebar. |

#### `Services/Audio/`
| File | Purpose |
|---|---|
| `AmbientPlayer.swift` | AVPlayer singleton: queue, shuffle, loop, volume, currentTime. `playURL(_:)` for ad-hoc playback. |
| `MediaLibrary.swift` | Legacy ambient library: SwiftData tracks + playlists + auto-categorization. Separate from `MediaCatalog`. |
| `MediaCategorizer.swift` / `PlaylistSynth.swift` / `LibraryAutoClean.swift` | Auto-grouping + cleanup for the ambient library. |

#### `Services/AI/`
| File | Purpose |
|---|---|
| `LLMProvider.swift` | Protocol: `generate(prompt:) async -> AsyncStream<String>` |
| `MLXProvider.swift` | On-device Apple Silicon inference via `mlx-swift-lm`. |
| `RemoteOpenAIProvider.swift` | OpenAI-compatible HTTP client (works with Ollama, vLLM, LM Studio, or any self-hosted OpenAI-format endpoint). |
| `GeminiProvider.swift` | Google AI Studio client with key rotation on 429. |
| `ThrottledCachedProvider.swift` | Wrapper: rate limit + summary cache (for Gemini free tier). |
| `AITextService.swift` | App-layer API: polish / summarize / continue / translate / grammar / classify. |
| `AIModelManager.swift` | MLX model download + state. |
| `SummaryCache.swift` | Vault-scoped JSON cache keyed by content hash. |
| `RateLimiter.swift` / `QuotaTracker.swift` | Token / RPM budgeting for free-tier providers. |

#### `Services/Download/`
| File | Purpose |
|---|---|
| `YTDLPLocator.swift` | Finds `yt-dlp` + `ffmpeg` binaries (`/opt/homebrew/bin`, `/usr/local/bin`, manual pick). |
| `YTDLPDownloader.swift` | Audio (mp3/m4a) and Video (mp4) modes; quality pickers; progress streaming. |
| `YTDLPSearch.swift` | `yt-dlp --match-title` search over YouTube. |
| `YTDLPMetadataBackfill.swift` | Re-fetch real Chinese/original titles for previously-downloaded files. |

#### `Services/Chat/`
| File | Purpose |
|---|---|
| `ChatSession.swift` / `ChatMessage.swift` | Per-note conversation SwiftData models. |
| `ChatStore.swift` | Transcript sidecars under `<vault>/.nextnote/chats/`. |
| `ChatService.swift` | Runs a message through `AITextService.currentProvider`. |

#### `Services/Dashboard/`
Dashboard view = pinned notes + AI-rolled summaries. Hands off to `AITextService`.

#### `Services/Digest/`
`DailyDigestService.swift` — fires once per day, summarizes recent vault activity.

#### `Services/Security/`
`KeychainStore.swift` — stores OpenAI / Gemini API keys. All access now off-main (`Task.detached`) so a slow `securityd` won't block the first window.

### Views

| Area | Files | Notes |
|---|---|---|
| `Views/ContentView.swift` | Main window: `NavigationSplitView { sidebar } detail: { editor }` | Gates on `libraryRoots.isConfigured`; falls back to `LibrarySetupView` |
| `Views/Setup/` | `LibrarySetupView` | First-run folder chooser |
| `Views/Sidebar/` | `LibrarySidebar` + `BooksSection` + `NotesSection` + `ExtraMediaPlayer` | Notes tree top (flex), Ebooks + Media collapsible trays bottom |
| `Views/Vault/` | `VaultTreeView` + `VaultPickerView` | Folder + file tree, rename / create / move via context menu |
| `Views/Editor/` | `EditorView` + `MarkdownPreviewView` + `MarkdownToolbar` + `MarkdownHighlighter` | NSTextView wrapper with Markdown syntax highlight + WKWebView preview |
| `Views/EPUB/` | `EPUBReaderView` + `EPUBContentWebView` + `EPUBReaderHost` + `BookLibraryView` | WKWebView-based chapter reader, JS bridge for selection + paging |
| `Views/AI/` | `AIChatPanelView` + `AIActionPanel` + provider pickers | Per-note chat + quick actions |
| `Views/Audio/` | `AmbientBar` + `MediaLibraryView` + `MediaPlayerView` | Dock-style ambient bar, full library sheet, pop-out video vibe window |
| `Views/Download/` | `YouTubeDownloadView` | Paste URL, pick mode, stream progress |
| `Views/Search/` | `SearchBarView` | In-document find (find next / previous) |
| `Views/Settings/` | `SettingsView` | AI provider, editor prefs, vault settings |
| `Views/TabBar/` | `TabBarView` | Open-notes tab strip |
| `Views/Dashboard/` | `DashboardEditorView` | `_dashboard.md` → pinned + AI summaries split |

### Utilities

| File | Purpose |
|---|---|
| `Utilities/nextNoteCommands.swift` | `NextNoteCommands: Commands` — every menu item + shortcut |

---

## 8. Feature Walk-Throughs

### 8.1 Notes

- Notes live as plain `.md` files under `<notesRoot>/`. Real folders become tree groups. Rename on disk = delete + insert (reconciled on rescan).
- `VaultStore.scan()` walks the tree, caps at 10 000 nodes, skips `.git` / `node_modules` / `.nextnote`. Only shows `.md` + images — binary / audio / video / epub go to their own sidebar sections.
- Each open note = one tab (`TabItem` in `AppState.openTabs`). Saves fire on Cmd+S, auto-save timer, and scene inactive.
- Atomic writes via `NoteIO.write(url:content:)`.

### 8.2 EPUB Reader

- Books land in `<ebooksRoot>/`. `BookLibrary.scan()` registers every `.epub` via `EPUBImporter.registerExisting` (hash-dedupe by `SHA256(epubBlob)`).
- `EPUBParser` unzips to `~/Library/Caches/nextNote/Books/<bookID>/` (never the vault — the OS can nuke Caches anytime; we regenerate on demand).
- `EPUBParser` reads `META-INF/container.xml` → OPF → manifest + spine + NCX (EPUB 2) or `nav.xhtml` (EPUB 3).
- Reader = `EPUBContentWebView` (`WKWebView`) with a JS bridge:
  - `nnHighlight` — selection → `BookHighlight` record
  - `nnScroll` — scroll ratio → persisted `Book.lastScrollRatio`
  - `nnBoundary` — page-end / page-start → auto-advance chapter
  - `nnPage` (injected) — keyboard / click paging
- Click left 30 % of page → prev page; right 30 % → next page; middle stays for text / links.
- TOC click resolves to a spine index (by `lastPathComponent`) + optional `#anchor`.
- Multi-root note: same XHTML file can appear for multiple TOC entries — we scroll to `#anchor` via `scrollIntoView`.
- Reader is embedded inline in the main detail pane (not a window / sheet). `appState.activeBookID` drives the switch; `.id(bookID)` forces SwiftUI to rebuild the view when the user picks a different book.

### 8.3 Media (Music + Video)

- `MediaCatalog.scan(mediaRoot:)` walks `<mediaRoot>/` on `.task(id: vault.root)` and after any `libraryRoots` change.
- Audio extensions: `mp3 m4a wav aac flac ogg`. Video: `mp4 mov m4v webm`. Edit `MediaKind.swift` to extend.
- Sidebar click:
  - Music → `AmbientPlayer.shared.playURL(url)`. Ad-hoc one-off Track, not persisted.
  - Video → `appState.activeMediaURL = url` → detail pane swaps to `ExtraMediaPlayer`.
- Ambient library (the older, heavier layer) lives in `Services/Audio/MediaLibrary.swift` and uses its own bookmark + SwiftData `Track` model. Accessible via **Media → Media Library…**.

### 8.4 AI

```
AITextService.shared
├── reconfigure()         — reads UserPreferences.aiProviderType
│   ├── .onDevice → MLXProvider(manager: AIModelManager.shared)
│   ├── .remote   → RemoteOpenAIProvider(baseURL, model, apiKey)
│   └── .gemini   → GeminiProvider(apiKeys) wrapped in ThrottledCachedProvider
└── currentProvider: any LLMProvider
```

- Keychain reads (`KeychainStore.get`) run on `Task.detached` — never block the main actor. (A slow `securityd` used to starve the first window; no longer.)
- Streaming: each provider returns `AsyncStream<String>`. Chat / continue-writing consumes chunks as they arrive.
- Caching: `SummaryCache` is per-vault (`<vault>/.nextnote/cache.json`). Keyed by `contentHash`; invalidated whenever a note's hash changes.
- Rate limiting: `RateLimiter` is shared across throttled providers so multiple dashboards don't blow the free-tier Gemini quota.

To add a new provider: implement `LLMProvider` + extend `AITextService.reconfigure()`.

### 8.5 YouTube Download

Requires `yt-dlp` (and optionally `ffmpeg`) installed.

1. **Media → Download from YouTube…** → `YouTubeDownloadView` sheet.
2. First run: `YTDLPLocator` auto-detects `/opt/homebrew/bin/yt-dlp` or `/usr/local/bin/yt-dlp`; otherwise user picks.
3. Paste URL or search query → `YTDLPDownloader.download(url:dest:mode:quality:ffmpeg:)` — sandboxed Process launch with `--no-playlist`, `--add-metadata`, etc.
4. Audio mode without ffmpeg → m4a. With ffmpeg → mp3 V0 VBR.
5. Video mode: mp4, quality picker (best / 1080p / 720p / 480p). Without ffmpeg effectively capped at 720p.
6. On success: file lands in `<mediaRoot>/` (default `~/Documents/nextNote/Media/`), gets registered with `MediaLibrary`, sidebar rescan picks it up.

**How the process talks to the sandboxed app**: both `yt-dlp` and `ffmpeg` are launched via `Process` with an explicit `executableURL`; the destination folder is inside the user-granted security-scoped bookmark (`libraryRoots.mediaRoot`), so the subprocess can write there.

### 8.6 Per-Note Chat

- `ChatSession` is keyed by vault-relative path → one persisted conversation per note.
- Transcripts live as `<vault>/.nextnote/chats/<path-hash>.json`.
- `ChatService.send(message:)` takes the note's content as context + the full chat history, calls `AITextService.currentProvider.generate(...)`, streams tokens into a new `ChatMessage`.

### 8.7 Daily Digest

- `DailyDigestService.generateIfDue()` fires once per calendar day, in vault mode, when a remote provider is configured.
- Scans recent vault notes, groups by `contentHash` changes, asks the model for a 1-paragraph rollup, writes it to `<vault>/_digest/YYYY-MM-DD.md`.

---

## 9. Configuration

All settings live in **Preferences** (⌘,):

### Editor

- Font, size, line spacing, line numbers, auto-indent, tab width, wrap.
- Auto-save interval (0 = manual only).

### AI

- Provider: On-device (MLX) / Remote (OpenAI-compatible) / Gemini.
- Per-provider: base URL, model ID, API key (Keychain).
- Disable-thinking toggle for Qwen-style remote servers (`chat_template_kwargs.enable_thinking=false`).
- Preferred AI language for outputs (zh-CN default).

### AI Model (on-device)

- Default: `mlx-community/Qwen3-4B-4bit` (~2.3 GB download).
- Any model with an MLX conversion on Hugging Face.
- Downloads stream to `~/Library/Application Support/<bundle>/models/`. First download needs a network + 1–5 min on Apple Silicon.
- Optional Hugging Face token (gated model access).

### Gemini

- Key(s) — comma- or newline-separated; the provider rotates on 429.
- Model ID: `gemini-flash-latest` (editable since Google rebrands these).

### Vault

- Accessed via **Library** menu, not Settings.

---

## 10. Extending nextNote

### Add a new file category to the sidebar

1. Extend `MediaKind` or add a new enum case in `FileCategory.classify(ext:)`.
2. Either add a bucket to `MediaCatalog` (for transient scans) or create a SwiftData `@Model` in `Models/`.
3. Add a view in `Views/Sidebar/` and mount it in `LibrarySidebar`.

### Add a new AI provider

1. Create `Services/AI/MyProvider.swift` implementing `LLMProvider`.
2. Extend `AIProviderType` enum + `AITextService.reconfigure()`.
3. Add a Settings panel under `Views/Settings/AIProviderSettings.swift`.

### Add a menu shortcut

Edit `Utilities/nextNoteCommands.swift`. Trigger via either a direct method call on a singleton, or by flipping an `AppState` one-shot trigger that a view `.onChange`s.

### Add a new SwiftData model

1. Define `@Model class` in `Models/`.
2. Add to the newest `NextNoteSchemaV*` models list in `SchemaVersions.swift`.
3. If schema is not backwards-compatible (rename, delete, type change), also add a `SchemaMigrationPlan`.

---

## 11. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| App launches but window never appears | `SecItemCopyMatching` blocked on `securityd` | Unlock login keychain via Keychain Access.app; we already run keychain reads on `Task.detached`, but first-time decrypt can still stall |
| "Could not access <path>" | Stale security-scoped bookmark | Library menu → Change <Kind> Folder… and re-pick |
| YouTube download: "yt-dlp not found" | `brew install yt-dlp` not on PATH the sandbox sees | Download sheet → Choose… and point to `/opt/homebrew/bin/yt-dlp` |
| EPUB: wrong chapter on switch | Known bug, fixed in `.id(bookID)` modifier on `EPUBReaderHost` | `git pull` |
| Ad-hoc signature blocks Gatekeeper | Unsigned build | `xattr -dr com.apple.quarantine /Applications/nextNote.app` |
| iCloud fills up with build artifacts | Xcode DerivedData inside iCloud | Confirm `BUILD_DIR := build.nosync/` (the Makefile already does this) |

Logs: `log stream --predicate 'process == "nextNote"' --level debug`

---

## 12. Contributing

1. Fork + branch.
2. `make build` must pass with no new warnings. Swift 6 strict concurrency is on.
3. Prefer editing existing files over adding new ones.
4. Comments only when the **why** is non-obvious — a hidden constraint, a workaround, a subtle invariant. Don't narrate what the code does; name things well instead.
5. No external telemetry. Ever.
6. One feature per PR.

### Directory additions

When you add a new feature directory under `Services/` or `Views/`, update Section 7 of this document.

### Tests

There is no test target yet. Highest-value candidates when someone wants to add one:

- `EPUBParser` (fixture EPUBs covering EPUB2 NCX, EPUB3 nav, cover detection, spine ordering).
- `XHTMLToMarkdown` (snapshot tests per tag).
- `NoteIO.sanitize` (filename edge cases).
- `RateLimiter` (concurrent request ordering).

---

## 13. License

(Pick one when you publish — MIT or Apache 2.0 is friendliest for a SwiftUI OSS app.)

Dependencies: MLX (MIT), ZIPFoundation (MIT), SwiftSoup (MIT), Apple platform frameworks.

---

## 14. Appendix — Quick Reference

### Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Save | ⌘S |
| Open file | ⌘O |
| New tab | ⌘T |
| Close tab | ⌘W |
| Next / prev tab | ⌘⇧] / ⌘⇧[ |
| Find in document | ⌘F |
| Toggle sidebar | ⌘1 |
| Focus mode | ⌘⇧\\ |
| Rescan library | ⌘R |
| Media play/pause | ⌥Space |
| Media next/prev | ⌘⌥→ / ⌘⌥← |
| Media Library | ⌘⇧M |
| AI rebuild dashboards | ⌘⇧R |
| AI summarize | ⌘⌥S |

### File Paths

| Kind | Default |
|---|---|
| Notes | `~/Documents/nextNote/Notes/` |
| Media | `~/Documents/nextNote/Media/` |
| Ebooks | `~/Documents/nextNote/Ebooks/` |
| Chat sidecars | `<notesRoot>/.nextnote/chats/` |
| AI summary cache | `<notesRoot>/.nextnote/cache.json` |
| EPUB unzip workspace | `~/Library/Caches/nextNote/Books/<bookID>/` |
| SwiftData store | `~/Library/Containers/com.nextnote.app/Data/Library/Application Support/default.store` |
| MLX model cache | `~/Library/Application Support/<bundle>/models/` |
| Build output | `./build.nosync/` |

### UserDefaults Keys (for debugging)

- `libraryRoot_notes` / `libraryRoot_media` / `libraryRoot_ebooks` — security-scoped bookmark blobs
- `vaultBookmark` — legacy single-root (migrated on first launch)
- `ambientAudioFolder` — legacy ambient library bookmark
- `ytdlp.binaryPath` / `ytdlp.ffmpegPath`
- `aiProviderType` / `remoteBaseURL` / `remoteModelId` / `geminiModelId`
- `vaultMode` (true by default in current builds)

Reset to pristine state:

```sh
defaults delete com.nextnote.app
rm -rf ~/Library/Containers/com.nextnote.app
rm -rf ~/Library/Saved\ Application\ State/com.nextnote.app.savedState
rm -rf ~/Library/Caches/nextNote
```

### Dependency versions (pinned in `project.yml`)

- `mlx-swift-lm` — branch `swift-tokenizers`
- `swift-tokenizers-mlx` — branch `main`
- `swift-hf-api-mlx` — branch `main`
- `ZIPFoundation` — `>= 0.9.19`
- `SwiftSoup` — `>= 2.7.0`

### Entitlements (`nextNote.entitlements`)

```xml
com.apple.security.app-sandbox                       true
com.apple.security.files.user-selected.read-write    true
com.apple.security.files.downloads.read-write        true
com.apple.security.assets.pictures.read-only         true
com.apple.security.network.client                    true
```

No Documents / Music / Movies category entitlements — we get to those folders via user-selected bookmarks instead, which is more flexible and survives migration.

---

That's the whole stack. Everything in one process, no background daemons, no external services required beyond the optional `yt-dlp` / `ffmpeg` / your own LLM server. Happy hacking.
