# nextNote — UX Audit (from a user's chair)

Cross-surface review of how the app feels, not what it does. Grouped by flow. Each finding has severity + suggested fix. Severity scale: **P0** block → **P1** confusing / frustrating → **P2** papercut → **P3** polish.

Most of the P0s here are fixed in the same commit as this audit; the P1/P2/P3 list is the follow-on roadmap.

---

## Fixed in this pass

### [P0] Media / Ebooks don't refresh when files are added outside the app
- **Symptom**: user drops `.mp3`, `.mp4`, `.epub` into their folder from Finder or a download. Sidebar stays stale until they manually hit **Library → Rescan** (⌘R).
- **Root cause**: only explicit triggers (app launch, root change, menu command) ran `rescanLibrary`.
- **Fix**: `ContentView` now rescans on `NSWindow.didBecomeKeyNotification` + every 15s while focused. Alt-tab back into the app → instant refresh.
- **File**: `Views/ContentView.swift` (`.onReceive(NSWindow.didBecomeKeyNotification)` + 15s loop)

### [P0] "Create new note" seems to fail when parent folder is collapsed
- **Symptom**: right-click folder → New Note → enter name → commit. Tree doesn't show it. User assumes broken.
- **Root cause**: `OutlineGroup` swallows its own expansion state internally — no API to programmatically expand after create.
- **Fix**: Replace `OutlineGroup` with recursive `DisclosureGroup` + `@State expandedPaths: Set<String>`. Auto-expand ancestors on create / rename / move. Rename preserves expansion of the renamed folder.
- **File**: `Views/Vault/VaultTreeView.swift` (`nodeRow`, `expansionBinding`, `expandAncestors`)

---

## Sidebar

### [P1] Sidebar scrollbars fight for space
- **Symptom**: Notes on top has its own scroll view; Ebooks tray has its own; Media tray has its own. On a laptop screen, long content in any one forces inner scrolls instead of using free space.
- **Fix**: consolidate into a single vertical scroll area, with Ebooks + Media trays as collapsible sections inside. Drop the per-tray `frame(maxHeight: 260)` caps.

### [P1] Trays collapsed-by-default would be cleaner
- Currently expanded-by-default. First-time user sees a cluttered sidebar even when empty.
- Persist per-tray state to `UserPreferences` via `@AppStorage`.

### [P2] No indicator when scan is in progress
- `mediaCatalog.isScanning` / `vault.isScanning` exist but sidebar doesn't show them.
- Add a tiny spinner next to the tray count when `isScanning && totalMedia == 0`.

### [P2] "Library sources" concept is gone but the Ebooks tray has no "add source" affordance
- If a user wants to add more EPUBs, they can only do it via **Library menu → Change Ebooks Folder…** (replaces, doesn't add). No way to aggregate multiple folders.
- Acceptable given the new "one folder per category" decision, but consider surfacing **Reveal in Finder** via a tray right-click.

### [P2] Books expanded TOC is cramped on deep trees
- 12pt indent per level; on chapter-heavy books the title column compresses to one word.
- Flatten to a max 2 levels; or make the sidebar wider by default.

### [P3] Drag-and-drop target feedback is missing
- Drag a note onto a folder → no hover highlight. You don't know if the folder accepts the drop.
- Add a `.dropDestination` highlight via `isTargeted` Binding.

---

## First launch / Setup

### [P1] Setup screen doesn't explain the difference between "Use Defaults" and "Change…"
- First-time user doesn't know whether the default paths will be created or must exist.
- Add a helper line under each row: *"Will create ~/Documents/nextNote/Notes if missing"*.

### [P2] No post-setup welcome
- Straight to an empty app. Consider a "You're ready — drag files into your folders, or press ⌘N to start" empty-state overlay for 5 seconds.

### [P3] Changing a root later doesn't move existing files
- User picks a new Ebooks folder; old books disappear from sidebar (they're in a different folder now). Might surprise them.
- Add a confirmation: *"Change Ebooks Folder? Your existing books stay where they are; the sidebar will now scan <new path>."*

---

## Notes editor

### [P1] No auto-save indicator
- Users trained on cloud apps expect a "saved" dot somewhere. nextNote saves every 30 s (configurable) + on blur — but no visual confirmation.
- Add a `·` indicator next to the tab title when the buffer is dirty; clears on save.

### [P1] Markdown toolbar is not discoverable on wide screens
- Lives at the top of the editor pane, above the text. On first glance users don't notice it and type plain markdown manually.
- Consider a compact floating toolbar that appears on text selection (like Notion / Medium). Or at minimum a tooltip hover.

### [P2] Split-pane preview doesn't scroll-sync with editor
- Users expect editing line 200 in the source to keep the preview around line 200. Currently independent scrolls.
- Track editor cursor line → proportionally position preview.

### [P2] `H` button in toolbar is unclear — defaults to H1, but pops a menu
- Icon-only label. Tooltip helps. Better: show the current level next to the H (`H1 ▾`).

### [P3] Font picker in Settings doesn't show preview
- Users don't know what "SF Mono" looks like vs "Menlo" without changing + scrubbing back.
- Inline live preview: *"The quick brown fox — SF Mono 16pt"*.

---

## EPUB reader

### [P1] Clicking edges of the page to paginate isn't discoverable
- No hint. Many users miss it.
- On first open, show a one-time overlay: *"← click here for previous page, click here for next →"*. Dismiss after first click.

### [P1] Table-of-contents column in sidebar gets stale when switching books
- If you expand book A's TOC, switch to book B, book A stays expanded. Noise.
- Auto-collapse all other books when user activates one.

### [P2] Highlight color picker is yellow-only from UI, but model supports pink/blue/green
- `BookHighlight.color` takes a string; UI never lets user pick.
- Add a color swatch row in the Highlights panel row + in a hover popover.

### [P2] No search-in-book
- `⌘F` searches the current note, not the EPUB chapter.
- Route the reader's webview through `WKWebView.find` when `appState.showSearchBar` is true and `activeBookID != nil`.

### [P3] Font size adjustment doesn't animate
- Press `A+` → text jumps. A 150ms easeInOut on the CSS var would feel much calmer.

---

## Media (Music + Videos)

### [P1] Playing a file doesn't show it's playing
- Current track title lives only in the AmbientBar at the bottom. Sidebar row doesn't highlight the now-playing item.
- Add an accent dot / row background on the current track.

### [P1] AmbientBar is too small on wide displays
- A tiny strip at the bottom. Controls cramped.
- Allow vertical expansion on hover → show the queue, scrubber, album art.

### [P2] Click-to-play always starts a one-off queue
- User expects: click first track → plays all tracks in the folder in order. Currently each click replaces the queue with a single item.
- Change `MediaListSection.onTap` to pass the full list + starting index to `AmbientPlayer.setQueue`.

### [P3] No album / folder grouping
- Music tray is flat alphabetical. Users with albums expect grouping.
- Group by parent folder name. Two-level tree inside Music.

---

## YouTube download

### [P1] No progress is visible while `yt-dlp` runs
- Sheet shows *"Downloading…"* spinner. Actual yt-dlp output (xx% ETA) is silenced.
- Parse progress lines from stdout; show a real progress bar.

### [P2] No "Cancel" button mid-download
- Once started, only way out is close the sheet.
- Wire a cancel action → kill the process subtree.

### [P3] "Detected yt-dlp at ..." is shown in the sheet but doesn't auto-apply
- User sees path, must still click **Choose…**. Confusing.
- Auto-adopt detected path on first open; let user override only if they want to.

---

## AI

### [P1] Model download silence
- First-time MLX model download sits at 0% for several minutes with no progress.
- Already tracked in `AIModelManager.modelState` but the UI only shows a generic "not downloaded" banner.
- Show MB downloaded / total + ETA.

### [P1] Switching providers mid-session doesn't clear the chat context
- Old transcript stays; next message goes to new provider. Results can be jarring.
- On provider change, add a system message: *"Switched to Gemini. Previous context kept."*

### [P2] Keychain prompts can block the first launch
- Already mitigated (keychain reads moved to `Task.detached`). If the system keychain is locked, user sees a hang.
- Detect the stall; show a banner: *"Waiting for keychain — unlock Keychain Access.app"*.

### [P3] "Continue Writing" has no way to specify length
- One-shot — runs, replaces. No "how many sentences" input.
- Add a length slider in the action panel.

---

## Menus

### [P1] "Library" menu has inconsistent capitalization with "Media"
- "Library" vs "Media Library". Users can't tell at a glance which is which.
- Rename Media menu's "Media Library" item to "Ambient Library…" (what it actually is — a legacy SwiftData-backed track db, separate from the new Library/Media folder).

### [P2] Keyboard shortcuts clash silently
- `⌘R` in View → Rescan, but most Mac apps use `⌘R` for "Reload" in a web context. Fine here but document it.
- `⌘S` for AI Summarize vs `⌘S` for Save — one uses ⌘⌥S, but users can miss the option. Add a tooltip hinting the shortcut is for AI.

### [P2] No way to discover shortcuts without reading the menu
- Standard Mac convention but could be friendlier.
- Add a Help menu entry: *"Keyboard Shortcuts…"* → cheat sheet sheet.

### [P3] Media menu is long (10+ items)
- Splits into ambient + YouTube + video-vibe + basic playback.
- Consider grouping YouTube + video-vibe into a submenu: **Media → Tools ▸**.

---

## Error handling

### [P1] Errors are silent or alerts
- vault errors → `lastError` string → banner.
- YouTube errors → alert sheet.
- EPUB parse errors → nothing visible; the book just doesn't show up.
- Fix: unify into a non-blocking notification at the bottom-right (macOS Ventura style). `appState.lastError` already exists — expose it in a StatusBarView consumable area.

### [P1] "Book not found" message has a dead-end "Back to Notes" button that does nothing useful
- Happens when a Book is deleted from SwiftData while activeBookID still refers to it.
- Gracefully fall back to the editor instead of showing the error at all.

### [P3] File importer accepts epub but silently drops it
- `FileType.openableUTTypes` includes epub, but `importFiles` tries to read it as UTF-8 text and fails silently.
- Skip binary types or route to `EPUBImporter.importEPUB`.

---

## Visual polish

### [P2] Inconsistent corner radii across surfaces
- Cards use 10pt, book cover cells use 6pt, menu tray headers use 0pt, buttons use system default.
- Pick one (8pt looks good) and apply across all custom surfaces.

### [P2] No dark-mode-specific accent adjustments
- `.accentColor.opacity(0.12)` reads as a soft tint in light mode, but nearly black in dark mode.
- Use adaptive SwiftUI colors (`.secondary.opacity` etc.).

### [P3] Book cover cells fill 200pt height even for portrait covers
- Wastes space when a book has a square or landscape cover.
- Aspect-fit with `min(200, image.height)`.

### [P3] Ambient bar does not have a subtle divider separating it from the editor
- Merges visually with whatever is above. Add a 0.5pt divider line.

---

## Performance / perception

### [P1] 15-second rescan timer could thrash on large Media folders
- On a `~/Music` with 10 k tracks, full rescan every 15s is wasteful.
- Upgrade to `FSEventStream` (recursive, push-based). Fallback to the timer only if FSEvents setup fails.

### [P2] VaultStore.scan rebuilds the whole tree on every mutation
- Comment says *"cheap enough for <10k nodes"*. At the boundary, UI flickers.
- Incremental updates: when `createNote(newPath)` lands, locally splice the new `FolderNode` into `tree` instead of full rescan.

### [P3] First-launch MLX model download blocks AI features
- Can't do AI until model is resident. 2.3 GB over a slow link = tens of minutes.
- Offer a "Gemini free tier" default during the download so users aren't blocked.

---

## Accessibility

### [P2] Color contrast of `foregroundStyle(.tertiary)` text on tinted backgrounds fails WCAG AA
- E.g. "Chapter 8 / 37 · 0%" in the reader bottom bar.
- Bump to `.secondary`.

### [P2] VoiceOver labels missing on icon-only buttons
- Toolbar buttons labeled only by `Image(systemName:)`. No `.accessibilityLabel`.
- Add labels across toolbar / reader / sidebar buttons.

### [P3] Keyboard navigation of the sidebar tree is partial
- Arrow keys move selection but don't expand / collapse.
- Implement space / ↵ on folder row → toggle expansion.

---

## Privacy surfacing

### [P2] Users don't know where their data lives
- Setup screen mentions `~/Documents/nextNote/`, then never again.
- Preferences pane or a `?` in the Library menu: *"Your notes are at ~/Documents/nextNote/Notes — click to open in Finder"*.

### [P3] No "export everything" affordance
- Data lives as plain files, which IS the export. But a "Reveal vault in Finder" button in Settings would make it discoverable.

---

## Roadmap suggestion

Order of attack (assuming one maintainer, iterating weekly):

1. **Week 1** — fix all P1s listed under **Sidebar + Notes editor** (the core writing loop).
2. **Week 2** — P1s under **EPUB reader + Media** (the reading/consumption loop).
3. **Week 3** — P1 model-download UX + AI provider-switch context feedback.
4. **Week 4** — visual polish pass + accessibility labels.
5. **Week 5** — FSEvents-based rescan + incremental tree updates (performance).
6. **Week 6** — one-time onboarding polish + shortcut cheat sheet.

---

## How to keep this honest

Re-read this doc after each release. For every "yeah but…" moment you had during testing, add it here with a severity. The moment something has ≥ 3 user reports, it graduates to P0 / P1.

The only thing worse than a bug is a bug everybody knows about and nobody tracks.
