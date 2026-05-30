# NextNote Code Index

Living one-line-per-file map of the codebase, plus a log of structural
changes and removed files. **Every code change must update this file** —
add/modify entries when files are added or change purpose, move deleted
files to "Removed files" with a date, and log refactors at the top.

This index is the first stop when:
- Onboarding (what's where, what each file does)
- Hunting redundancy (a future cleanup pass)
- Deciding where a new file belongs

---

## Structural changes (newest first)

- **2026-05-30 — Drawing → PDF export.** Drawings (`.nndraw`) can now be
  exported to a multi-page PDF (one drawing page → one PDF page, Letter or
  background-aspect). New `Services/Export/DrawingPDFRenderer.swift` (pure
  CoreGraphics) + `Views/Editor/DrawingDocumentView+Export.swift` (gathers live
  canvas state). Smoothing factored into a shared `cgSmoothedPath` in
  `+Rendering` so on-screen and exported ink are identical; `pageRenderHeight`
  made internal for reuse. Wiring: a bottom-bar Export button, and File >
  Export as PDF (⇧⌘E) now dispatches in `exportActiveNoteAsPDF()` — drawing tabs
  (a `.nndraw` note, or a markdown note showing its Draw layer) fire the new
  `AppState.triggerDrawingExportPDF` one-shot that the live view observes;
  markdown tabs keep the WKWebView path.
- **2026-05-26 — Round 2 optimization: god-file splits + shared helpers + bug fix.**
  Split four large view/service files along their existing MARK boundaries so
  each piece sits in its own file:
    - `DrawingDocumentView.swift` (951 → 577) + `+Editing` / `+Media` / `+Persistence` / `+Rendering`
    - `ChatTerminalView.swift` (700 → 422) + `+Commands` (/search,/meeting) / `+BlockActions`
    - `LibraryReconciler.swift` (506 → 158) + `+Plan` / `+Apply`
    - `PDFReaderView.swift` (549 → 266) + sibling `PDFReaderAnnotation.swift` / `PDFKitView.swift`
  Tradeoff: `@State private var` widened to `@State var` so cross-file
  extensions can see state — standard SwiftUI codebase practice; nothing
  outside each view's own extensions reaches in.
  New shared helpers: `Utilities/StringExtras.swift` (`nilIfEmpty`),
  `Utilities/SecurityScope.swift` (`URL.withSecurityScope { }`),
  `Services/EPUB/BookHashing.swift` (streamed SHA-256). EPUBImporter +
  PDFImporter now share the hash + dropped `import CryptoKit`; the inline
  `nilIfEmpty` extension that lived in PDFImporter is gone.
  **Bug fix:** restored `struct DrawStroke` in `DrawingDoc.swift` — the
  previous commit deleted `DrawingCanvasView.swift` along with the struct
  the live drawing editor depends on; clean builds would have failed
  without this.
- **2026-05-26 — Sidebar dead-code purge + DrawingSheet retire + NotesSection trim.**
  Removed the orphaned Assets/Ebooks tray scaffolding (deleted 4 files, slimmed
  `LibrarySidebar.swift` 184 → 14 lines). Retired the floating `DrawingSheet` /
  `DrawingWindowController` duplicate of the drawing UX in favour of the full
  `DrawingDocumentView` editor — removed its toolbar button (`MarkdownToolbarView`),
  call site (`EditorAreaView.openDrawingWindow`), and the two source files plus
  the orphan `DrawingCanvasView` it owned. Tightened `NotesSection` header
  ("Files <vault>" → just the vault name). Net: **-1500 lines, -6 files**.
- **2026-05-26 — Release pipeline fully local (m1pro retired).**
  Created a local Developer ID cert via Xcode; rewrote
  `~/.claude/skills/nextnote-release/scripts/release.sh` to sign/notarize
  entirely in `/tmp` (sidesteps iCloud fileprovider's xattr race with
  codesign); idempotent version bump. SKILL.md / infra.md / memory updated.
  0.6.0 was the first release cut end-to-end on this Mac.
- **2026-05-26 — 0.6.0 release.** Drawing: lasso select (move/delete/recolor),
  conservative shape recognition (line/rect/ellipse/triangle), smoothed ink
  rendering. New `ShapeRecognizer.swift`.
- **2026-05-23 — 0.5.0 release.** YouTube link embedding in markdown notes
  (bare URL on its own line → inline player) and drawing notes
  (movable/resizable thumbnail card → click to play). Card CRUD: single-click
  select, ✕ delete, drag move, corner resize, ⌫ key. Fixed Error 152 by
  embedding via `youtube-nocookie.com` origin. New `YouTubeEmbedWebView.swift`.
- **2026-05-23 — 0.4.0 release.** Handwriting / drawing notes (`.nndraw`):
  re-editable JSON strokes, multi-page, PDF/screenshot backgrounds, placed
  images. PDF reader enhancements. UX cleanup: segmented sidebar tabs,
  terminal chrome, Workflow menu (was AI menu), ⌘K palette wand.

## Removed files (newest first)

- 2026-05-26: `Views/Editor/DrawingSheet.swift`, `Views/Editor/DrawingCanvasView.swift` — floating quick-sketch surface, superseded by `DrawingDocumentView`.
- 2026-05-26: `Views/Sidebar/LibrarySidebar+Assets.swift`, `Views/Sidebar/LibrarySidebar+Ebooks.swift`, `Views/Sidebar/BooksSection.swift`, `Views/Sidebar/LibrarySidebar+Shared.swift` — Assets/Ebooks tray UI, replaced by the unified `NotesSection` file tree in 0.4.0.

---

## App entry

- `nextNoteApp.swift` — `@main`; window scene, environment object wiring (AppState, VaultStore, LibraryRoots, AssetCatalog, PinnedFoldersStore, BacklinksIndex, TagsIndex).

## Models (`nextNote/Models/`)

- `AppState.swift` (+`+DailyNote.swift`, `+OpenExternal.swift`) — app-wide observable: open tabs, focused note, one-shot triggers (new drawing, export PDF, rescan, etc.).
- `AIProvider.swift`, `AIProviderSettings.swift`, `VectorDBSettings.swift` — AI/embedding provider config types.
- `Book.swift`, `BookHighlight.swift` — SwiftData `@Model` for ebooks + highlights.
- `ChatBlock.swift`, `ChatMessage.swift` — per-note chat session types.
- `DownloadJob.swift` — YouTube download job state.
- `DrawingDoc.swift` — `.nndraw` Codable model + in-memory ink types: `DrawingDoc` / `DrawPage` / `PlacedImage` / `PlacedVideo` / `DrawStroke` / `CodableStroke` (tolerant v1→v3 decode).
- `FileCategory.swift`, `FileType.swift`, `MediaKind.swift` — file classification enums.
- `FolderNode.swift` — generic folder/file tree node used by VaultTreeScanner + PinnedFoldersStore.
- `Note.swift` — disk-backed note index (V2+ schema).
- `PinnedFolder.swift` — pinned external folder model (id, name, bookmark, tree).
- `SchemaVersions.swift` — SwiftData schema migration definitions (V1→V2 etc.).
- `TextDocument.swift` — `@Model` in-memory document buffer for every open `TabItem` (title + content + fileType). Started life as the V1 disk-persistence type; in V2+ the disk source-of-truth moved to files on disk + a `Note` index row, but this type is still the editor's working copy. 18 files depend on it — retire only with a tab-layer rewrite + SwiftData migration.
- `Track.swift` — media track metadata.
- `UserPreferences.swift` — `@AppStorage`-backed app preferences (vaultMode, theme, etc.).

## Services

### AI (`Services/AI/`)
- `AIService.swift` — top-level provider router (polish/summarize/translate/grammar/continue).
- `BookMetadataAI.swift` — AI-suggested title/author for ebook auto-rename.
- `EmbeddingPipeline.swift`, `VectorStore.swift`, `SemanticSearchService.swift`, `TextChunker.swift` — Postgres+pgvector pipeline for ebook semantic search.
- `FolderCategorizer.swift` — AI suggests destination folder for new media.
- `TavilyClient.swift` — Tavily web-search API client.

### Audio (`Services/Audio/`)
- `AmbientPlayer.swift`, `AmbientFolderBookmark.swift` — bottom-bar AmbientBar player + its folder bookmark.
- `MediaLibrary.swift` (+`+Scan`, `+Tracks`, `+Playlists`, `+AmbientFolder`) — disk-backed media catalog, scans Media root, persists.
- `MediaPlayback.swift`, `MediaScanner.swift`, `MediaTrackPersistence.swift`, `PlaylistPersistence.swift` — playback + scan + on-disk persistence helpers.
- `LibraryAutoClean.swift`, `LibraryReconciler.swift` (+`+Plan`, `+Apply`), `MediaCategorizer.swift`, `PlaylistSynth.swift`, `TidyMediaPrompt.swift`, `TrackTitleFormatter.swift` — library tidy + AI auto-categorize + title cleanup (uses `yt-dlp` for metadata). `LibraryReconciler` is a namespace enum: main file holds data shapes + leaf helpers, `+Plan` builds the audit (incl. AI merge proposal), `+Apply` executes it.

### Download (`Services/Download/`)
- `YTDLPLocator.swift` — finds `yt-dlp` binary on the user's machine (Homebrew etc.).
- `YTDLPDownloader.swift`, `YTDLPSearch.swift`, `YTDLPMetadataBackfill.swift` — wrappers around the `yt-dlp` CLI.
- `DownloadJobCoordinator.swift` — background download queue + ffmpeg post-processing.

### EPUB (`Services/EPUB/`)
- `EPUBParser.swift`, `EPUBImporter.swift`, `BookLibrary.swift` — EPUB OPF/NCX parsing + library scanner.
- `BookHashing.swift` — streamed SHA-256 helper shared by `EPUBImporter` and `PDFImporter` for dedupe.
- `PDFImporter.swift` — adds PDFs to the ebook library.
- `XHTMLToMarkdown.swift` — EPUB → Markdown.
- `EbookLibraryActions.swift`, `TidyEbooksPrompt.swift` — context-menu actions + AI tidy.

### Export (`Services/Export/`)
- `PDFExporter.swift` — renders Markdown notes to PDF (used by the Draw layer's "annotate over note text" too). `ContentView.exportActiveNoteAsPDF()` dispatches: drawing tabs route to the drawing exporter, everything else to this WKWebView path.
- `DrawingPDFRenderer.swift` — pure CoreGraphics multi-page PDF writer for `.nndraw` drawings (one drawing page → one PDF page; white paper, full-bleed background, placed images, video cards, smoothed ink). Takes resolved CGImage/CGPath/CGColor primitives — no SwiftUI. A final PDFKit pass adds clickable YouTube link annotations over video cards.

### Media (`Services/Media/`)
- `AssetCatalog.swift`, `AssetLibraryActions.swift` — asset folder model + context-menu actions.
- `MediaFolderMerger.swift` — auto-consolidate scattered media into the Media root.
- `VideoExporter.swift` — video export helpers.

### Security (`Services/Security/`)
- `KeychainStore.swift` — generic keychain wrapper (AI API keys, app-specific creds).

### Vault (`Services/Vault/`)
- `VaultStore.swift`, `VaultBookmark.swift`, `VaultMigrator.swift` — vault root, security-scoped bookmark, legacy bookmark migration.
- `LibraryRoots.swift` — three roots: Notes / Media / Ebooks.
- `VaultTreeScanner.swift` — builds `FolderNode` tree off the main actor.
- `VaultFSActions.swift`, `NoteIO.swift`, `NewDocumentRouter.swift`, `FileImportRouter.swift` — file-system operations (create / move / trash / atomic write).
- `VaultSaveCoordinator.swift` — debounced save coordinator for notes.
- `DrawingIO.swift`, `DrawingAssets.swift` — `.nndraw` atomic JSON read/write + asset (PNG) save helpers + PDF page rasterizer.
- `BacklinksIndex.swift`, `TagsIndex.swift` — vault-wide indexes (rebuilt on edit).
- `WikiLinkResolver.swift` — resolves `[[wikilink]]` targets.
- `PinnedFoldersStore.swift` — persists user-pinned external folders (security-scoped bookmarks, UserDefaults key `nextnote.pinnedFolders`).

## Utilities (`nextNote/Utilities/`)

- `nextNoteCommands.swift` — `Commands` builder: File/Edit/Workflow/Library menus + key shortcuts.
- `MarkdownHighlighter.swift` — syntax highlighting for the markdown editor.
- `FrontmatterParser.swift` — YAML frontmatter parser (title override, tags).
- `AssetURL.swift`, `FileDestinations.swift`, `FinderActions.swift`, `PasteboardActions.swift` — small helpers.
- `StringExtras.swift` — `String.nilIfEmpty` (turns "" into nil).
- `SecurityScope.swift` — `URL.withSecurityScope { … }` wrapper around `startAccessingSecurityScopedResource` / `defer { stop }`.

## Views

### Root + shared
- `Views/ContentView.swift` — root NavigationSplitView, environment wiring, global one-shot triggers.
- `Views/Common/HSplitOrVStack.swift` — responsive layout helper.
- `Views/Root/ContentToolbars.swift` — top toolbar wiring.

### Sidebar (`Views/Sidebar/`)
- `LibrarySidebar.swift` — two-section shell: `NotesSection` + `PinnedFoldersSection`.
- `NotesSection.swift` — sidebar header + the `VaultTreeView` tree.
- `PinnedFoldersSection.swift` — collapsible list of user-pinned external folders; hidden when empty.

### Vault tree (`Views/Vault/`)
- `VaultTreeView.swift` (+`+Rows`, `+Actions`, `+Toolbar`, `+Context`) — the main file tree (rows, drag/drop, context menu, toolbar).
- `VaultPickerView.swift` — first-launch folder picker.

### Editor (`Views/Editor/`)
- `EditorView.swift`, `EditorAreaView.swift`, `EditorContentRouter.swift` — routes the active tab to the right surface (markdown, drawing, PDF, EPUB, media, etc.).
- `MacTextEditorView.swift`, `IOSTextEditorView.swift` — platform-specific text editor backings.
- `MarkdownToolbarView.swift` — quick-insert snippet toolbar (headings, lists, code, table, link, image, hr, math, footnote).
- `MarkdownToHTML.swift`, `MarkdownHTMLWrapper.swift`, `MarkdownPreviewView.swift`, `MarkdownEmbeds.swift` — markdown → HTML pipeline (image / video / audio / YouTube embeds) + WKWebView preview.
- `YouTubeEmbedWebView.swift` — NSViewRepresentable WKWebView player loading the `youtube-nocookie.com` embed (used by the drawing canvas's video card).
- `EditorFontResolver.swift` — font picker resolver.
- `FocusModeView.swift` — distraction-free editor mode.
- `DrawingDocumentView.swift` (+`+Editing`, `+Media`, `+Persistence`, `+Rendering`, `+Export`) — `.nndraw` editor: pages, strokes, PDF/screenshot backgrounds, placed images, placed YouTube videos, lasso/shape/smoothed-ink tools. Main file = view shell + toolbar + page rendering + zoom; siblings hold ink-mutation + media insertion + load/save + static stroke helpers + PDF export respectively. `+Export` gathers live canvas state (caches + smoothed paths) into `DrawingPDFRenderer`; reachable from the bottom-bar button or File > Export as PDF (⇧⌘E).
- `ShapeRecognizer.swift` — freehand stroke → idealized line/rect/ellipse/triangle (conservative; returns nil when not a confident match).
- `BacklinksPopover.swift` — status-bar backlinks list popover.
- `PreviewWindowController.swift` — singleton NSWindow for the floating Markdown preview.
- `StatusBarView.swift` — bottom-of-editor status bar (reading time, save dot, backlinks).

### AI (`Views/AI/`)
- `AISummarySheet.swift` — ⌥⌘S streaming summary.
- `ChatBlockRow.swift`, `ChatTerminalView.swift` (+`+Commands` for `/search`+`/meeting`, `+BlockActions` for copy/retry/delete), `ChatTerminalWindowController.swift` — per-note chat UI + standalone-window controller.

### Assets / Audio / Media / Download / EPUB / Search / Settings / Setup / TabBar / Terminal / FileManager — see filenames, all roughly self-describing wrappers around their Service-layer counterparts.

---

## Maintenance rule

When you change code in this repo:
1. **Update the per-file entry** if you added a new file, renamed one, or
   materially changed its purpose. Keep entries to one line.
2. **Move deleted files** to "Removed files" with the date + a 1-line reason
   (so future reviewers don't recreate what was intentionally cut).
3. **Log refactors / cross-file changes** at the top of "Structural changes"
   with the date and a 2–4-line summary.

Doing this every change keeps the codebase lean and lets the next audit
pass spot redundancy in minutes instead of hours.
