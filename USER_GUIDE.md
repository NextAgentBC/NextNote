# nextNote — User Guide

A local-first Mac app for your notes, books, and media. Everything stays on your Mac as plain files. No account, no cloud, no tracking.

---

## Install

### Easy way — download the release

1. Go to the **[Releases page](https://github.com/NextAgentBC/NextNote/releases)**.
2. Grab the latest `nextNote-<version>.dmg`.
3. Open the DMG, drag **nextNote** into **Applications**, eject.
4. First launch: right-click the app → **Open** (one time only). macOS asks *"Are you sure you want to open it?"* — click **Open**.

The signed release (v0.1.0+) is **notarized by Apple** — double-click and run, no Gatekeeper warnings.

If you build from source or grab an older ad-hoc signed build, macOS may refuse to open it. Unblock once:

```sh
xattr -dr com.apple.quarantine /Applications/NextNote.app
```

### From source

See [README.md](README.md#quick-start).

---

## First launch — pick your folders

When you open nextNote for the first time, you'll see a **Welcome** screen with three folders to set up:

- **Notes** — where your `.md` notes live
- **Media** — where your music and videos live
- **Ebooks** — where your `.epub` books live

You have three options:

1. **Click "Use Defaults for All"** — nextNote creates three folders under `~/Documents/nextNote/` (Notes / Media / Ebooks) and you're done.
2. **Click "Change…" on any row** — pick a folder you already have. E.g. point Media at your existing `~/Music` folder, or Ebooks at wherever you keep your books.
3. **Mix both** — defaults for some, existing folders for others.

Click **Start** and the main window opens.

You can change any of the three later from the **Library** menu.

---

## The main window

```
┌────────────────────┬──────────────────────────────┐
│  Notes ▾           │                              │
│    📁 journal      │                              │
│    📄 2026-04-22   │    Editor / Reader /         │
│    📄 todo.md      │    Media Player              │
│                    │                              │
│                    │    (whatever you clicked     │
│  ▸ Ebooks (3)      │     in the sidebar)          │
│  ▸ Media (12)      │                              │
└────────────────────┴──────────────────────────────┘
```

- **Top of the sidebar**: your Notes tree — folders and `.md` files. Click any note to open it in a tab.
- **Bottom of the sidebar**: two collapsible trays for **Ebooks** and **Media**. Click the title to expand.
- **Main area on the right**: whatever you most recently opened — the Markdown editor, the EPUB reader, or a media player.

---

## 📝 Writing notes

### Create a note

- **New Document** (⌘N via the toolbar) — creates `Untitled.md` in your current sidebar folder.
- Or right-click a folder in the sidebar → **New Note…**.

Notes are saved to disk automatically (every 30 seconds by default; configurable in Settings → Editor). Cmd+S saves immediately.

### Folders

- Drag notes between folders in the sidebar to move them on disk.
- Right-click a folder → **New Folder…** to create a subfolder.
- Right-click any item → **Rename / Delete / Reveal in Finder**.

### Markdown

Write plain Markdown. The editor syntax-highlights headings, bold, italics, code, links.

The toolbar above the editor has shortcuts for:

- Heading levels (H1–H6)
- Bold / italic / strike-through
- Inline code / code block
- Quote
- Bulleted / numbered list
- Link / image
- Horizontal rule
- Math (`$$…$$`)
- Table

### Preview

Toggle between **Editor / Split / Preview** from the toolbar (or **View → Preview Mode**). Split is useful for writing; Preview gives you a clean read.

Images in your note (`![](path/to/pic.jpg)`) render live. Paths are resolved relative to the note's folder.

### Search

**⌘F** opens find-in-document. Replace + regex + case-sensitive options are in the bar.

### Focus mode

**⌘⇧\\** hides everything except the text. Click the arrow in the bottom-right to exit.

### Tabs

Each open note is one tab across the top of the editor. Close with **⌘W**, next/prev with **⌘⇧]** / **⌘⇧[**.

---

## 📚 Reading ebooks

### Add books

Drop any `.epub` file into your Ebooks folder (default `~/Documents/nextNote/Ebooks/`). nextNote scans it automatically the next time you open the app — or right now via **Library → Rescan Library** (⌘R).

### Read

- Click the **Ebooks ▸** tray at the bottom of the sidebar to expand it.
- Click a book title → the reader opens in the main area + the book's chapter list (TOC) expands under it in the sidebar.
- Click any chapter → jumps to it.

### In the reader

- **Click the right edge of the page** (or Space / → / ↓) → next page.
- **Click the left edge** (or ← / ↑) → previous page.
- **⌘[** / **⌘]** → previous / next chapter.
- Page past the end of a chapter → auto-advances to the next one.

### Highlights

- Select text with the mouse → it's highlighted + saved automatically.
- **Highlights** button in the reader toolbar → panel with every highlight in the book. Click a highlight to jump back to it. Trash icon to delete.

### Themes + text size

Reader toolbar:

- **Palette icon** — Light / Sepia / Dark.
- **A−** / **A+** — smaller / larger text.
- **X** — close the reader, go back to notes.

### Picking up where you left off

nextNote remembers the current chapter + scroll position per book. Close the reader, open the book again weeks later — same page.

---

## 🎵 Music & 🎬 Videos

### Add media

Drop `.mp3 / .m4a / .wav / .flac / .aac / .ogg` or `.mp4 / .mov / .m4v / .webm` into your Media folder. Use subfolders for albums, playlists, whatever.

Subfolders are walked recursively — anything under the Media root is fair game.

### Play

- Click the **Media ▸** tray at the bottom of the sidebar → expand.
- **Music**: click any track → starts playing in the ambient bar at the bottom of the window. Controls there for pause / next / prev / volume / shuffle / loop.
- **Videos**: click any clip → plays inline in the main area. X button to close.

Supported formats depend on what macOS can natively decode (AVFoundation). If a file won't play, its extension is probably unsupported — convert with `ffmpeg` or VLC.

### Media menu

- **⌥Space** — play/pause
- **⌘⌥→** / **⌘⌥←** — next / previous track
- **Media Library** (⌘⇧M) — the full library view with playlists, categories, etc.
- **Video Vibe Window** — pop-out video into its own small floating window so it keeps playing while you work in another tab.

---

## 📥 YouTube download

*Optional — requires `yt-dlp` installed via Homebrew.*

Install yt-dlp (one time):

```sh
brew install yt-dlp
brew install ffmpeg     # optional but recommended (unlocks mp3 + 1080p+)
```

Then in nextNote:

1. **Media → Download from YouTube…** (or click the ↓ in the ambient bar).
2. First time: click **Choose…** next to "yt-dlp binary" and pick `/opt/homebrew/bin/yt-dlp`. The file picker lands you there — just press **Open**.
3. (Same for ffmpeg if you want it.)
4. Paste a YouTube URL.
5. Choose **Audio** (mp3) or **Video** (mp4). Pick quality if you want.
6. Click **Download**.

Progress shows in the bar. When done, the file lands in your Media folder and appears in the sidebar.

**Search mode**: paste a search query instead of a URL, hit **Search YouTube**. Top results come back — click the one you want to download.

---

## 🤖 AI assistant

nextNote has built-in AI for polish / summarize / continue / translate / grammar check.

### Picking a provider

Open **Settings → AI** and choose:

- **On-device (MLX)** — runs on your Mac, offline, free. Apple Silicon only. First run downloads a model (~2.3 GB, the default is Qwen3-4B-4bit). Slower than cloud but truly private.
- **Remote (OpenAI-compatible)** — point at your own Ollama, LM Studio, vLLM, or any OpenAI-format HTTP endpoint. Set the URL + model name.
- **Gemini** — Google's free tier. Paste an API key from [Google AI Studio](https://aistudio.google.com/). Supports multiple keys (comma-separated) with auto-rotation when one hits the quota.

You can switch providers anytime; they all expose the same features.

### Use it

- **AI panel** (brain icon in the toolbar, or ⌘⇧I) — opens a side panel below the editor.
- Pick an action (Polish / Summarize / Continue / Translate / Grammar / Simplify) and click **Run AI**.
- Replace your note with the result, or copy it.

### Per-note chat

The AI panel remembers a conversation per note. Talk about the current note — ask it to explain, critique, expand. Transcript lives in `<notes>/.nextnote/chats/` as JSON alongside your notes.

### Daily Digest

If you've picked a remote or Gemini provider, nextNote rolls up your recent note changes into a daily digest. Fires once per calendar day — find the output at `<notes>/_digest/YYYY-MM-DD.md`.

Run on demand: **AI → Run Daily Digest Now**.

---

## Library management

The **Library** menu controls your three root folders:

- **Change Notes Folder…** / **Change Media Folder…** / **Change Ebooks Folder…** — moves the root to a different path. Your files aren't moved; nextNote just starts scanning the new location instead.
- **Reveal Notes / Media / Ebooks in Finder** — opens the folder.
- **Rescan Library** (⌘R) — re-scans all three after you drop new files in.

Tip: changing the Media root to `~/Music` lets nextNote show every track on your Mac.

---

## Settings

Open with **⌘,**.

- **Editor** — font, size, line spacing, auto-save interval, line numbers, tab width, wrap.
- **AI** — provider, API keys, model IDs.
- **Preferences** — default language, preview mode default.

API keys are stored in the macOS Keychain, never in plaintext.

---

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Save | **⌘S** |
| Open file | **⌘O** |
| New tab / note | **⌘T** / **⌘N** |
| Close tab | **⌘W** |
| Next / previous tab | **⌘⇧]** / **⌘⇧[** |
| Find in document | **⌘F** |
| Toggle sidebar | **⌘1** |
| Focus mode | **⌘⇧\\** |
| Rescan library | **⌘R** |
| Media play/pause | **⌥Space** |
| Media next / prev | **⌘⌥→** / **⌘⌥←** |
| Media Library | **⌘⇧M** |
| AI panel | **⌘⇧I** |
| AI rebuild dashboards | **⌘⇧R** |
| Previous / next chapter (reader) | **⌘[** / **⌘]** |

---

## Troubleshooting

**"The app is damaged and can't be opened."**
`xattr -dr com.apple.quarantine /Applications/nextNote.app`

**"Could not access …" on a folder.**
The saved security-scoped bookmark went stale (you moved / renamed the folder). Library menu → **Change <Kind> Folder…** and re-pick.

**YouTube download says yt-dlp not found.**
`brew install yt-dlp`, then in the download sheet click **Choose…** and point to it — usually `/opt/homebrew/bin/yt-dlp`.

**EPUB won't open.**
Not every EPUB is well-formed. Try opening it in another reader first. If it works there but not here, file a bug and attach the EPUB if you can.

**AI is slow / spinning.**
On-device model may still be downloading — check **Settings → AI Model** for progress. Remote provider may be unreachable — check your URL + API key.

**Window won't appear on launch.**
Rare, usually caused by a stuck macOS keychain prompt behind another app. Quit nextNote, unlock login keychain via **Keychain Access.app**, relaunch.

---

## Privacy & data

Everything is local:

- **Notes** → plain `.md` files in your Notes folder. Open with any text editor. Version-control with git if you want.
- **Ebooks** → the original `.epub` files. We add a small index row in `~/Library/Containers/com.nextnote.app/`.
- **Music / videos** → your files, untouched.
- **AI keys** → macOS Keychain.
- **Chat transcripts** → `<notes>/.nextnote/chats/*.json`. Delete the folder to wipe history.
- **AI summaries cache** → `<notes>/.nextnote/cache.json`. Safe to delete.

Nothing leaves your Mac unless you choose a remote AI provider — and even then, only the prompts you send to that provider.

---

## Asking for help

- **Bugs / feature requests** → [Issues](https://github.com/NextAgentBC/NextNote/issues)
- **Questions** → [Discussions](https://github.com/NextAgentBC/NextNote/discussions)
- **Contributing** → see [TUTORIAL.md](TUTORIAL.md)

---

*NextNote is open source under the Apache License 2.0. Enjoy.*
