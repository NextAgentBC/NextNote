# NextNote — User Guide

A local-first Mac app for your notes, books, and media. Everything lives on your Mac as plain files. No account, no cloud, no tracking.

New to NextNote? This guide walks through every feature from zero. Skim the Table of Contents if you just want one thing.

---

## 📖 Table of Contents

1. [Install](#install)
2. [First launch — set up your folders](#first-launch--set-up-your-folders)
3. [The main window](#the-main-window)
4. [📝 Notes](#-notes)
5. [📚 Ebooks (EPUB reader)](#-ebooks-epub-reader)
6. [🎵 Music & 🎬 Videos — playback](#-music---videos--playback)
7. [✂️ Video editing](#️-video-editing)
8. [🖼️ Asset Library](#️-asset-library)
9. [📥 YouTube download](#-youtube-download)
10. [🤖 AI assistant](#-ai-assistant)
11. [🗂️ Library management](#️-library-management)
12. [⚙️ Settings](#️-settings)
13. [⌨️ Keyboard shortcuts](#️-keyboard-shortcuts)
14. [🔒 Privacy & data](#-privacy--data)
15. [🆘 Troubleshooting](#-troubleshooting)
16. [🗺️ What's coming next](#️-whats-coming-next)
17. [💬 Asking for help](#-asking-for-help)

---

## Install

### Easy way — download the release

1. Go to the **[Releases page](https://github.com/NextAgentBC/NextNote/releases)**.
2. Grab the latest `nextNote-<version>.dmg`.
3. Open the DMG, drag **NextNote** into **Applications**, eject.
4. First launch: right-click the app → **Open** (one time only). macOS asks *"Are you sure you want to open it?"* — click **Open**.

The signed release (v0.1.0+) is **notarized by Apple** — double-click and run, no Gatekeeper warnings.

If you build from source or grab an older ad-hoc build, macOS may refuse to open it. Unblock once:

```sh
xattr -dr com.apple.quarantine /Applications/NextNote.app
```

### From source

See [README.md](README.md#quick-start). This path is for developers — if you're just here to use the app, use the DMG above.

---

## First launch — set up your folders

On first launch NextNote shows a **Welcome** screen with four folders to configure:

- **📝 Notes** — where your `.md` notes live
- **🎵 Media** — music and videos
- **📚 Ebooks** — `.epub` books
- **🖼️ Assets** — visual scratch material (images / short clips / audio) you want to drop into notes

Three options:

1. **"Use Defaults for All"** — NextNote creates four folders under `~/Documents/nextNote/` and you're done.
2. **"Change…" on any row** — pick an existing folder. E.g. point Media at `~/Music`, or Ebooks at wherever you keep books.
3. **Mix both** — defaults for some, existing folders for others.

Click **Start** and the main window opens.

> **Tip:** you can change Notes / Media / Ebooks roots later from the **Library** menu. The Assets folder lives at `~/Documents/nextNote/Assets/` by default.

### Ambient Library (separate prompt)

Right after folder setup, NextNote may ask *"Set up your ambient library?"* — this is a long-term home for the **ambient player** (a track collection separate from the Media folder tray). Click **Choose Folder…** to point it at your music root, or **Skip** and do it later via **Media → Set Ambient Library Folder…**.

---

## The main window

```
┌────────────────────┬──────────────────────────────┐
│  Notes ▾           │                              │
│    📁 journal      │                              │
│    📄 2026-04-22   │   Editor / Reader /          │
│    📄 todo.md      │   Media Player /             │
│                    │   Asset preview              │
│  ▸ Ebooks (3)      │                              │
│  ▸ Media (12)      │   (whatever you clicked      │
│                    │    in the sidebar)           │
├────────────────────┴──────────────────────────────┤
│  ▶  Now Playing — Taylor Swift · Cardigan         │
└───────────────────────────────────────────────────┘
```

- **Top of the sidebar** — Notes tree. Folders + `.md` files. Click to open in a tab.
- **Bottom of the sidebar** — collapsible trays for **Ebooks** and **Media**. Click a tray title to expand.
- **Main area** — the most recent thing you opened: editor, EPUB reader, video player, or asset preview.
- **Ambient Bar (bottom)** — whatever music or video is playing right now. Controls tuck away when not needed.
- **Toolbar (top)** — Open File • New Note • Find • Preview Mode picker • AI Panel (⌘⇧I) • Focus Mode (⌘⇧\\).

---

## 📝 Notes

Plain `.md` files on disk. Your notes are just text — readable with any editor, version-controllable with git.

### Create & organize

- **New note**: click the **+ (New Document)** button in the toolbar, or right-click a folder in the sidebar → **New Note…**.
- **New folder**: right-click a folder in the sidebar → **New Folder…**.
- **Move**: drag a note between folders in the sidebar (highlight shows the target).
- **Rename / Duplicate / Delete / Reveal in Finder**: right-click any note or folder.
- **Copy as Markdown embed** (on media files in the tree): right-click → generates an `![](…)` snippet you can paste into a note.

New items automatically expand their parent folder so you can always see what you just created.

### The Markdown editor

Write plain Markdown. Headings, bold, italic, code, and links get live syntax highlighting.

The toolbar above the editor is a shortcut palette — click icons to insert snippets at the cursor:

- **Headings** (H1–H4)
- **Inline**: bold, italic, strikethrough, inline code
- **Blocks**: blockquote, bulleted list, numbered list, task list
- **Code block** — drop-down with language presets: Swift / Python / JavaScript / TypeScript / Java / C++ / Go / Rust / HTML / CSS / JSON / YAML / SQL / Bash
- **Tables** — size presets: 2×2, 3×3, 4×3, 5×3
- **Link / Image** / **Horizontal rule** / **Footnote**
- **Math** — inline `$…$` and display `$$…$$`, rendered with KaTeX in the preview

### Preview modes

Toolbar or **View → Preview Mode** switches between **Editor**, **Split**, **Preview**:

- **Editor** — plain text, fastest.
- **Split** — editor on the left, live preview on the right. Drag the divider to resize.
- **Preview** — clean read-only view.

Images and media embedded in Markdown (`![](path/to/pic.jpg)`) render live. Paths resolve relative to the note's folder. Video and audio files use `<video>` / `<audio>` with native controls.

### Tabs

Every open note is a tab at the top of the editor.

- **⌘T** — new tab
- **⌘W** — close current tab
- **⌘⇧]** / **⌘⇧[** — next / previous tab
- **Right-click a tab** — Close / Close Others / Save
- Modified tabs show a filled circle instead of the close × until you save.

### Find & replace (⌘F)

The find bar opens at the top of the editor.

- Live **match count** (X/Y)
- **Aa** toggle — case-sensitive
- **.*** toggle — regex
- **⌘G** / **⌘⇧G** — next / previous match
- Chevron expands the **replace** row: Replace current, Replace all
- **Esc** closes the bar

### Focus mode (⌘⇧\\)

Hides everything except the text. Click the arrow in the bottom-right to exit.

### Status bar

The strip at the bottom of the editor shows:

- **File type picker** — click to override (Markdown, Text, JSON, HTML, …)
- **Word count / character count / line count** — live as you type
- **Encoding** (UTF-8)

### Auto-save

Saves every 30 s by default (configurable in **Settings → Editor**). Also saves on tab switch, app background, and ⌘S.

---

## 📚 Ebooks (EPUB reader)

### Add books

Drop any `.epub` into your Ebooks folder (default `~/Documents/nextNote/Ebooks/`). NextNote scans automatically on next launch — or right now via **Library → Rescan Library** (⌘R).

Sub-folders under Ebooks become **groups** in the sidebar tray, so you can organize by author / series / genre. Book cover thumbnails show in the book library grid.

### Read

- Click the **Ebooks ▸** tray at the bottom of the sidebar to expand it.
- Click a book title → reader opens in the main area; the book's TOC expands under it in the sidebar.
- Click any chapter → jumps to it.

### In the reader

- **Click the right edge of the page** (or Space / → / ↓) → next page.
- **Click the left edge** (or ← / ↑) → previous page.
- **⌘[** / **⌘]** → previous / next chapter.
- Paging past the end of a chapter auto-advances to the next one.

### Highlights

- Select text with the mouse → it's highlighted + saved automatically.
- **Highlights** button in the reader toolbar → panel with every highlight in the book. Click to jump; trash icon to delete.

### Themes + text size

Reader toolbar:

- **Palette icon** — Light / Sepia / Dark.
- **A−** / **A+** — smaller / larger text.
- **X** — close the reader.

### Picking up where you left off

NextNote remembers the current chapter + scroll position per book. Close the reader, reopen it weeks later — same page. The book library is sorted by "last opened" by default so your current read stays on top.

### Managing books

- Right-click a book → **Reveal in Finder** or **Remove from Library** (the `.epub` stays on disk; NextNote just drops its index entry).

---

## 🎵 Music & 🎬 Videos — playback

### Add media

Drop any of these into your Media folder:

- Audio: `.mp3` / `.m4a` / `.wav` / `.flac` / `.aac` / `.ogg`
- Video: `.mp4` / `.mov` / `.m4v` / `.webm`

Sub-folders are walked recursively — anything under the Media root is fair game. Use folders for albums, playlists, whatever.

### Play from the sidebar

- Expand the **Media ▸** tray at the bottom of the sidebar.
- **Audio** → click a track → plays in the **Ambient Bar** at the bottom of the window.
- **Video** → click a clip → plays inline in the main area. Also shows a thumbnail in the Ambient Bar.

> **Format note:** NextNote uses macOS's native decoder (AVFoundation). If a file won't play, its codec is probably unsupported — convert with `ffmpeg` or VLC.

### The Ambient Bar

The strip at the bottom is your always-on music / video controller.

- **Play / Pause / Previous / Next** transport buttons
- **Scrubber** — click or drag to seek
- **Volume slider**
- **🔀 Shuffle** — random within the queue; remembers the setting
- **🔁 Loop queue** — replay the whole queue when it ends
- **+** — file picker to add audio to your library and queue
- **Video thumbnail** (when playing video) — double-click to pop the video into its own **Video Vibe Window**, so it keeps playing while you switch tabs
- **Collapse arrow** — hide the full controls, keep just the title

### Sidebar right-click menu

**On a media folder**: Play All • Play Shuffled • Enqueue • Reveal in Finder.

**On a single audio / video file**: Play • Enqueue • Reveal in Finder.

> When you enqueue a video, the Video Vibe Window pops out automatically so it doesn't cover your notes.

### Merging folders

Drag one sub-folder onto another in the Media tray — NextNote merges the contents. Typical use: `GEM 邓紫棋` dragged onto `邓紫棋`, collapsing two spellings of the same artist.

### Media menu

- **⌥Space** — play / pause
- **⌘⌥→** / **⌘⌥←** — next / previous track
- **⌘⇧M** — open the full **Media Library** (see below)
- **⌘⇧A** — open the **Asset Library**
- **Toggle Video Vibe Window** — pop the current video into a floating window

### Media Library (⌘⇧M)

A full library manager for the ambient collection.

- **All Tracks** view + a **Playlist** sidebar — create, rename, delete playlists.
- **Filter** by kind: All / Audio / Video.
- **Multi-select** with ⌘-click for batch operations.
- **Right-click a track** — Play • Play Next • Add to Playlist (sub-menu) • Rename Title / Rename File • Remove from Library.
  - **Rename Title** changes only the displayed name — the file on disk is untouched.
  - **Rename File** physically renames the file (keeps the extension).
- **Drop audio or video files** anywhere in the window → imports them.

#### AI-assisted cleanup (Media Library toolbar)

- **Restore Titles** — for tracks that downloaded with mangled names (e.g. `_xY1pq7.mp3`), AI re-fetches the real title from YouTube, including non-ASCII names (Chinese / Japanese / Korean).
- **Auto-Clean** — AI extracts *performer* + *song title* from messy file names and **moves** each file into a `<Category>/<Performer>/` folder, with a tidied filename.
- **Generate Playlists from Folders** — AI turns your folder structure into playlists.

Each of these is idempotent — running it again re-uses cached results when the content hasn't changed.

---

## ✂️ Video editing

The inline video player isn't just for playback — it's also a light editor. Open any `.mp4` / `.mov` by clicking it in the Media tray; the editor buttons live in the toolbar under the player.

### Trim (scissors icon ✂️)

1. Click **Trim**.
2. macOS's native trim bar appears across the bottom of the video — drag the yellow handles to set start and end.
3. Click **Save** (or press Enter).
4. A save-panel asks where to export. Suggested name: `<original>-trim.mp4`.

The original file is untouched; you get a new clipped copy.

### Remove audio

One click — strips the audio track and exports `<original>-muted.mp4`.

### Concatenate videos

1. Open the first video → **Add to Concat Queue**.
2. Open the next video → **Add to Concat Queue**. Repeat.
3. The queue shows below the player: numbered 1, 2, 3, … Drag to reorder. The minus icon removes an item; **Clear All** empties the queue.
4. Click **Export Concat** (⌘E) — needs ≥ 2 items. Pick a destination. Suggested name: `concat.mp4`.
5. A progress overlay shows percent complete. Errors show inline if anything fails.

> **Heads up:** concat re-encodes on the fly via AVFoundation — depending on length + your Mac, it can take from seconds to several minutes. Don't quit until the progress overlay closes.

### Where exports land

Wherever you picked in the save panel. The new file **does not** automatically land in the Media folder — if you want it catalogued, save it there (or drag it in afterward).

---

## 🖼️ Asset Library

A dedicated grid of **visual scratch material** — images, clips, voice memos — that you use across your notes. Think of it as your project's image/media drawer.

### Open it

**Media → Asset Library** or **⌘⇧A**.

### Import

- **Drag files from Finder** anywhere onto the grid → copied into your Assets folder. Duplicate names auto-suffix with `-2`, `-3`, …
- **Import button** (toolbar) — manual file picker.

### Browse

- **Filter** — segmented picker: All / Images / Videos / Audio.
- **Search** — filename search, live.
- **Thumbnails** — real image thumbs for stills; video thumbs grabbed at ~0.5 s (skips black intro frames); audio falls back to a waveform icon.

### Drag into a note

Grab any cell → drag it onto the Markdown editor → NextNote inserts the right embed for you:

- Image → `![title](path)`
- Video → `<video controls>` block
- Audio → `<audio controls>` block

The preview renders all three natively.

### Preview + trim

Double-click any cell → full-size preview sheet. Videos get the same **Trim** editor from the main video player (scissors button), so you can clip right out of the Asset Library.

### Right-click menu

- **Preview**
- **Reveal in Finder**
- **Copy Markdown Embed** — drops `![title](path)` onto the clipboard
- **Move to Trash** — confirms before deleting

### Where assets live

`~/Documents/nextNote/Assets/` by default (created automatically on first open). Plain files — back up with Time Machine, sync with anything.

---

## 📥 YouTube download

*Optional feature — needs two tiny command-line tools (`yt-dlp` and `ffmpeg`), installed through Homebrew. Never touched the Terminal before? No problem — the whole setup takes about 10 minutes, and you only do it once.*

### Step 0 — install Homebrew (skip if you already have it)

Homebrew is the standard "app store" for command-line tools on macOS. Everything below uses it.

1. Open **Terminal**: press **⌘Space** (Spotlight), type `Terminal`, hit **Return**. A black (or white) window with a blinking cursor appears — that's it.
2. Copy the official installer command from [brew.sh](https://brew.sh) (same as the line below), paste it into Terminal, and press **Return**:

   ```sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

3. It'll ask for your **Mac login password**. Type it and press Return — you won't see the characters as you type, that's a security feature, not a bug. Installation then runs for 3–10 minutes depending on your network.
4. When it finishes, Homebrew prints **"Next steps"** at the bottom with two lines starting with `echo …`. On an Apple Silicon Mac (M1/M2/M3/M4) they look like this:

   ```sh
   echo >> ~/.zprofile
   echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
   eval "$(/opt/homebrew/bin/brew shellenv)"
   ```

   **Copy the exact block Homebrew printed for you** (not the example above — yours may differ) and paste it into Terminal, press Return. This is the step most beginners miss; it's what lets Terminal find `brew` next time.
5. Verify: type `brew --version` and press Return. You should see something like `Homebrew 4.x.x`. If you get `command not found: brew`, close Terminal completely (⌘Q), reopen it, and try again.

### Step 1 — install yt-dlp (and ffmpeg)

Still in Terminal:

```sh
brew install yt-dlp
brew install ffmpeg     # optional but strongly recommended — unlocks mp3 export + 1080p/4K video
```

Each line takes 10–60 seconds. Verify:

```sh
yt-dlp --version        # prints a date-like version, e.g. 2025.09.26
ffmpeg -version         # only if you installed it
```

If both print a version, you're done with Terminal — you can close it.

### Step 2 — point NextNote at them

1. **Media → Download from YouTube…** (or click the ↓ in the ambient bar).
2. First time only: click **Choose…** next to "yt-dlp binary". The file picker opens in the right folder automatically — just press **Open**. If it doesn't, navigate to:
   - `/opt/homebrew/bin/yt-dlp` on Apple Silicon Macs (M1/M2/M3/M4)
   - `/usr/local/bin/yt-dlp` on older Intel Macs

   (These folders are hidden by default. Press **⌘⇧G** in the file picker and paste the path.)
3. (Same for ffmpeg, if you installed it.)

### Step 3 — download

The download sheet gives you two input modes:

- **Paste a YouTube URL** → direct download.
  - If you paste a **channel or playlist URL**, NextNote warns you and only downloads the first video.
- **Type a search query** → click **Search YouTube** → pick a result from the list → download.

Options:

- **Audio** (default) — mp3 V0 VBR if you have ffmpeg; m4a otherwise.
- **Video** — mp4. Quality picker: **Best / 1080p / 720p / 480p / 360p**. Without ffmpeg, effectively capped at 720p.

Click **Download**. Progress shows in the sheet; the file lands in your Media folder and appears in the sidebar.

### Auto-classify (optional toggle)

With **Auto-Classify** on (audio downloads), after the file arrives NextNote asks AI to extract *performer* + *song title* and moves the file into `<Category>/<Performer>/` inside your Media root. It canonicalises mixed-language artist names too — so **G.E.M.** lands in the **邓紫棋** folder, not a separate one.

### Post-download transcoding

YouTube only ships H.264 up to 1080p; higher tiers come as VP9 or AV1, which AVPlayer can't always decode (silent picture on older Macs / Intel). After a successful download NextNote probes the file and — only if the video track is VP9 or AV1 — re-encodes it to HEVC (`hvc1`) in place via hardware. H.264 / HEVC downloads pass through untouched.

### Repair existing downloads

If you already have a pile of VP9 / AV1 videos from earlier downloads, run the bundled script once:

```sh
scripts/repair-videos.sh ~/Documents/nextNote/Media
scripts/repair-videos.sh ~/Documents/nextNote/Media --dry-run   # preview only
```

It re-encodes only the files that need it; everything else is left alone.

---

## 🤖 AI assistant

Built-in AI that can polish, summarize, continue, translate, grammar-check, and chat — all against the note you're currently in, or the whole folder.

### Choose a provider

Open **Settings → AI** and pick one of:

- **On-device (MLX)** — runs locally on Apple Silicon. Fully offline, free, private. First run downloads a model (~2.3 GB; default is **Qwen3-4B-4bit**). Slower than cloud but your text never leaves the Mac. You can also pick **Gemma 4** (needs a HuggingFace token — the Settings pane has a 4-step setup flow).
- **Gemini** — Google's free tier. Paste an API key from [Google AI Studio](https://aistudio.google.com/). Supports **multiple keys** (one per line) with auto-rotation when one hits the daily quota. The pane shows live usage: *requests today / daily limit* with a progress bar.
- **Remote (OpenAI-compatible)** — point at any OpenAI-format HTTP endpoint: **Ollama**, **LM Studio**, **vLLM**, a self-hosted inference server, or any of the many Chinese providers that expose OpenAI-compatible APIs (DeepSeek, 通义, Qwen hosted, etc.). Set the base URL + model name + (optional) API key.
  - **Disable model thinking** toggle — Qwen-specific optimization; skips chain-of-thought tokens, faster and cheaper.

You can switch providers any time. All three expose the same actions.

> **Preferred AI Language** (Settings → AI) decides what language the AI replies in — independent of provider.

### Actions on the current note

Open the **AI panel** with **⌘⇧I** (brain icon in the toolbar). The panel docks below the editor.

| Action | What it does | Options |
|---|---|---|
| **Summarize** | Condenses the note | Length: Brief / Medium / Detailed |
| **Polish** | Rewrites for flow | Style: Concise / Casual / Professional / Formal |
| **Continue Writing** | Streams more text in your voice | — |
| **Translate** | Translates the note | Target: English / 中文 / 日本語 / 한국어 / Français |
| **Grammar Check** | Bullet list of issues | — |
| **Simplify** | Shortened, plainer version | — |

Pick an action → **Run AI** → the result appears in the panel. From there you can **Replace** your note with the output or **Copy** to clipboard.

> The AI menu items **Summarize / Polish / Continue / Translate / Grammar Check** are placeholders today — they'll run from the menu in a future release. Use the AI panel for now.

### Per-note chat

The AI panel has a chat transcript — one per note, persisted to disk under `<notes>/.nextnote/chats/`.

Header controls:

- **Doc toggle** — include the full text of the current note as context
- **Folder toggle** — include sibling notes' titles + excerpts
- **Trash icon** — clear this chat history

Send with **⌘Enter**. If the conversation gets long, earlier messages drop out of context (a notice appears) — the transcript itself is preserved.

### Folder dashboards

For every folder, NextNote can maintain a `_dashboard.md` file — a split-pane page with:

- **Pinned** (top) — your own notes, editable freely
- **AI section** (bottom) — automatically regenerated summary of the folder's contents

Controls:

- Header shows relative path + last-regenerated timestamp ("2 hours ago") + **Regenerate** button
- **AI → Rebuild All Dashboards** (⌘⇧R) rebuilds every folder in one pass

Results are cached by content hash — re-running doesn't re-call the API unless notes have changed.

### Daily Digest

Once per calendar day, NextNote rolls up your recent note changes into a digest file at `<notes>/_digest/YYYY-MM-DD.md`. Runs automatically on first launch of the day if you've picked a remote or Gemini provider.

Trigger manually: **AI → Run Daily Digest Now**.

---

## 🗂️ Library management

The **Library** menu controls your three main library roots. (Assets is managed from the Media menu.)

- **Change Notes Folder… / Change Media Folder… / Change Ebooks Folder…** — move a root to a different path. Your files aren't moved; NextNote just scans the new location.
- **Reveal Notes / Media / Ebooks in Finder** — opens the folder.
- **Rescan Library** (⌘R) — re-scans after you drop new files in.

NextNote also **auto-rescans** every 15 seconds while the app is focused, and immediately when you Cmd-Tab back from another app — so new files generally show up on their own.

> **Tip:** set the Media root to `~/Music` and NextNote surfaces every track on your Mac.

---

## ⚙️ Settings

Open with **⌘,**. Grouped into tabs:

### Appearance

- **Theme** — System / Light / Dark
- **Font** — SF Mono / Menlo / Courier / SF Pro / New York
- **Font size** (12–36 pt) • **Line spacing** (1.0–2.5)
- **Show line numbers** • **Wrap lines**

### Editor

- **Default file type** — type of new documents
- **Auto-indent** • **Tab width** (2 / 4 / 8 spaces)
- **Auto-save interval** — 15 s / 30 s / 1 min / 5 min / **Manual only**

### AI

- **Enable AI Features** toggle
- **Preferred AI Language** picker
- **Provider** picker (see [Choose a provider](#choose-a-provider))
- Per-provider settings: model, API key(s), endpoint URL, test-connection, usage quota

API keys are stored in the macOS **Keychain**, never in plaintext on disk.

### Vault

- **Enable vault mode** — switch the sidebar from the flat SwiftData list to the folder tree (recommended)
- **Change Vault…** / **Forget Vault**
- **Rescan** button

### Sync

- **iCloud Sync** — future feature, see [What's coming next](#️-whats-coming-next).

---

## ⌨️ Keyboard shortcuts

### File & tabs

| Action | Shortcut |
|---|---|
| Save | **⌘S** |
| Open File… | **⌘O** |
| New Tab | **⌘T** |
| Close Tab | **⌘W** |
| Next / previous tab | **⌘⇧]** / **⌘⇧[** |

### Editor

| Action | Shortcut |
|---|---|
| Find in document | **⌘F** |
| Find next / previous | **⌘G** / **⌘⇧G** |
| Close find bar | **Esc** |
| Toggle sidebar | **⌃⌘S** |
| Focus mode | **⌘⇧\\** |

### Library & media

| Action | Shortcut |
|---|---|
| Rescan Library | **⌘R** |
| Play / Pause | **⌥Space** |
| Next / previous track | **⌘⌥→** / **⌘⌥←** |
| Media Library | **⌘⇧M** |
| Asset Library | **⌘⇧A** |
| Export Concat (video editor) | **⌘E** |

### EPUB reader

| Action | Shortcut |
|---|---|
| Previous / next chapter | **⌘[** / **⌘]** |
| Page forward | **Space** / **→** / **↓** |
| Page back | **←** / **↑** |

### AI

| Action | Shortcut |
|---|---|
| Toggle AI panel | **⌘⇧I** |
| Send chat message | **⌘Enter** |
| Rebuild All Dashboards | **⌘⇧R** |

### Settings

| Action | Shortcut |
|---|---|
| Open Settings | **⌘,** |

---

## 🔒 Privacy & data

Everything is local:

- **Notes** → plain `.md` files in your Notes folder. Open with any text editor. Version-control with git if you want.
- **Ebooks** → the original `.epub` files. NextNote adds a small index row in `~/Library/Containers/com.nextnote.app/`.
- **Music / videos** → your files, untouched.
- **Assets** → your files under the Assets folder, untouched.
- **AI keys** → macOS Keychain.
- **Chat transcripts** → `<notes>/.nextnote/chats/*.json`. Delete the folder to wipe history.
- **AI summaries cache** → `<notes>/.nextnote/cache.json`. Safe to delete.
- **Dashboards** → `_dashboard.md` inside each folder. Plain Markdown.
- **Daily digests** → `<notes>/_digest/YYYY-MM-DD.md`. Plain Markdown.

**Nothing leaves your Mac** unless you pick a remote AI provider — and even then, only the prompts you send to that provider. With the **on-device (MLX)** provider, every byte of AI input and output stays local.

---

## 🆘 Troubleshooting

**"The app is damaged and can't be opened."**
`xattr -dr com.apple.quarantine /Applications/NextNote.app`

**"Could not access …" on a folder.**
The saved security-scoped bookmark went stale (you moved / renamed the folder). **Library menu → Change <Kind> Folder…** and re-pick.

**Terminal says `command not found: brew` right after installing Homebrew.**
You skipped the "Next steps" block Homebrew printed (the two `echo` lines). Scroll up in Terminal, find it, copy and paste the whole block. Then close Terminal (⌘Q) and reopen it. See [Step 0 of the YouTube section](#step-0--install-homebrew-skip-if-you-already-have-it).

**YouTube download says yt-dlp not found.**
Run `brew install yt-dlp` in Terminal. Then in NextNote's download sheet click **Choose…** and point to `/opt/homebrew/bin/yt-dlp` (Apple Silicon) or `/usr/local/bin/yt-dlp` (Intel). If the folder is hidden in the file picker, press **⌘⇧G** and paste the path.

**Downloaded YouTube video plays silently at 1440p / 4K.**
That means post-download transcoding didn't run. Fix existing files once: `scripts/repair-videos.sh <your media folder>`. New downloads transcode automatically.

**Video export / concat seems stuck.**
Depending on clip length + your Mac, an export can take several minutes. Don't quit the app until the progress overlay disappears.

**EPUB won't open.**
Not every EPUB is well-formed. Try opening it in another reader. If it works there but not in NextNote, file a bug and attach the EPUB if you can.

**AI is slow / spinning.**
On-device model may still be downloading — check **Settings → AI** for progress. Remote provider may be unreachable — click **Test connection**.

**Gemini says "quota exceeded".**
Free tier has per-minute and per-day limits. Add more keys (one per line in the API Keys box) — NextNote rotates automatically. Or switch to on-device for a while.

**Window won't appear on launch.**
Rare, usually a stuck macOS Keychain prompt behind another app. Quit NextNote, unlock login keychain via **Keychain Access.app**, relaunch.

---

## 🗺️ What's coming next

NextNote is actively developed. Planned for upcoming releases:

### Media creation & editing

- **🖼️ Image editing** — crop, rotate, annotate (arrows, text, highlights), brightness / contrast / saturation. Launch from Asset Library preview, like the video Trim editor today.
- **🎚️ Audio editing** — trim, fade in / out, normalize loudness, speed change, optional noise reduction. Same "open from Asset Library or Media tray → edit → export" shape as video.
- **📹 Screen recording** — capture full screen / window / region, optional mic + system audio, cursor visibility toggle. Clips land straight in the Media folder (or Assets, your choice) for drag-into-notes.

### AI

- **Direct native providers** beyond the OpenAI-compatible bridge:
  - **Anthropic Claude** — `claude-opus`, `claude-sonnet`, `claude-haiku`
  - **OpenAI** — `gpt-4o`, `gpt-5`, reasoning models
  - **Chinese providers** — DeepSeek, 通义千问 (Qwen), 文心一言 (ERNIE), Kimi, 豆包 — with one-click presets so you don't have to hunt for API base URLs
- **Deeper AI actions** that a stronger model unlocks:
  - **Long-context summaries** across an entire folder or whole notebook (map-reduce over chunks)
  - **Iterative rewrite** — generate → self-critique → revise, so the "Polish" output is genuinely better than a one-shot
  - **Semantic search** across all notes — not just filename/keyword
  - **Auto-tagging & auto-linking** — AI suggests tags and cross-links related notes
  - **Notebook Q&A (RAG)** — ask a question, get an answer grounded in your own notes, with citations

### Sync

- **iCloud sync** of Notes and library bookmarks across your Macs.

> These are directional — exact scope and order may shift between releases. Track progress in the [CHANGELOG](CHANGELOG.md) and [Issues](https://github.com/NextAgentBC/NextNote/issues).

---

## 💬 Asking for help

- **Bugs / feature requests** → [Issues](https://github.com/NextAgentBC/NextNote/issues)
- **Questions** → [Discussions](https://github.com/NextAgentBC/NextNote/discussions)
- **Contributing** → see [TUTORIAL.md](TUTORIAL.md)

---

*NextNote is open source under the Apache License 2.0. Enjoy.*
