# Demo assets

Sample files bundled with NextNote so first-time users can see every surface light up without hunting for content. All assets are public-domain or CC-licensed — feel free to distribute, modify, or delete.

| File | Kind | License | Source |
|---|---|---|---|
| `alice-in-wonderland.epub` | Book | Public domain | [Project Gutenberg #11](https://www.gutenberg.org/ebooks/11) |
| `sample-clip.mp4` | Video / MP4 (10 s, 360p) | CC BY 3.0 — © Blender Foundation | [Big Buck Bunny](https://peach.blender.org/about/) via test-videos.co.uk |
| `notes/welcome.md` | Note | MIT (this repo) | — |
| `notes/keyboard-shortcuts.md` | Note | MIT (this repo) | — |
| `notes/ai-setup.md` | Note | MIT (this repo) | — |

## Try it

1. Launch NextNote.
2. In the **Welcome** screen, click **Use Defaults for All** → **Start** (or pick your own folders).
3. Copy everything from this `demo/` folder into the matching roots:
   ```sh
   cp demo/notes/*.md          ~/Documents/nextNote/Notes/
   cp demo/alice-in-wonderland.epub ~/Documents/nextNote/Ebooks/
   cp demo/sample-clip.mp4     ~/Documents/nextNote/Media/
   ```
4. Back in NextNote press **⌘R** (View → Rescan Library) or just wait — the app auto-scans on window focus.

You should see:

- A **Notes** tree on the left with three markdown notes.
- An **Ebooks** tray with **Alice's Adventures in Wonderland**. Click to open; click a chapter in the sidebar to jump.
- A **Media** tray → **Videos** → **sample-clip**. Click to play in the ambient bar at the bottom.

## Remove demo content

Everything here is just files — `rm -rf ~/Documents/nextNote/{Notes,Ebooks,Media}/...` to nuke, or delete from the sidebar.
