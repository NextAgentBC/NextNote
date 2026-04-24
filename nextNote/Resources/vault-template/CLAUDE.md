# nextNote Vault — Agent Briefing

This vault is both a notes archive and a long-lived agent context. Follow the
contract below every session.

## On every session start

1. Read `99_System/Soul.md` — apply tone, voice, values, relationships.
2. Scan `99_System/memory/MEMORY.md` — load memory files whose description
   matches the current topic. Don't load every file; load what's relevant.
3. Check today's daily note at `10_Daily/$(date +%F).md`. If it exists, treat
   it as the current working context before anything else.

## Folder contract

| Folder         | Purpose                                                                 | Who writes       |
|----------------|-------------------------------------------------------------------------|------------------|
| `00_Inbox/`    | Unprocessed captures — raw ideas, no formatting required                | Human or agent   |
| `10_Daily/`    | YYYY-MM-DD.md, time anchor, episodic memory                              | `/start-my-day`  |
| `20_Project/`  | Active initiatives with frontmatter `status / phase`                    | `/kickoff`       |
| `30_Research/` | Structured investigations (intermediate)                                | `/research`      |
| `40_Wiki/`     | Compiled atomic knowledge, one concept per file. **Write only via `/ingest`** | `/ingest`, `/lint` |
| `50_Resources/`| Long-term reference pointers (tools, courses, bookmarks)                | Human            |
| `60_Canvas/`   | `YYYY-Www/` — weekly work canvas (sources, outline, drafts)             | `/weekly-canvas` |
| `70_Swipe/`    | Outlier structures worth imitating: `posts/`, `titles/`, `hooks/`       | `/swipe-save`    |
| `80_Raw/`      | Immutable source material. **Write only via `/ingest` or `/swipe-save`**| `/ingest`        |
| `90_Plans/`    | Execution drafts. Completed → `90_Plans/Archives/`                      | `/research`      |
| `99_System/`   | Soul, memory, prompts, templates, skills                                | Agent + human    |

## Slash-workflow index

Knowledge side (long-term compounding):
- `/ingest <url|path>` — pull source into `80_Raw/`, compile into `40_Wiki/`
- `/query <question>` — read `40_Wiki/index.md`, answer with citations
- `/lint` — validate links, index, orphans; auto-fix deterministic issues
- `/parse-knowledge <source>` — URL/PDF/YT → atomic wiki + derived prompt

Creator side (weekly cadence):
- `/weekly-canvas` — open or create `60_Canvas/$(date +%G-W%V)/`
- `/swipe-save <url|paste>` — classify into `70_Swipe/{posts,titles,hooks}`
- `/coach` — propose one content action based on Soul + current canvas + swipe
- `/brand-strategy`, `/content-engine`, `/offer-builder` — Dan Koe three pillars

Daily / admin:
- `/start-my-day` — review yesterday + inbox + active projects → daily note
- `/kickoff <inbox-item>` — promote inbox idea to a project with phases
- `/research <topic>` — plan-then-execute research loop
- `/archive <project-or-canvas>` — move to archives, preserve context
- `/ask <question>` — one-shot Q&A without file writes

Maintenance:
- `/consolidate-memory` — merge duplicate memories, prune stale ones
- `/raw-gc` — clean `80_Raw/` files not referenced by any wiki for 90+ days
- `/publish-ready` — review current canvas drafts for ship-ready pieces

## Always

- Prefer `/query` (reads compiled wiki) over training-knowledge recall.
- Cite wiki paths when answering from them: `40_Wiki/<topic>/<concept>.md`.
- Update `99_System/memory/` when you learn non-obvious user facts.
- Use `YYYY-MM-DD` for every date; never relative dates.

## Never

- Guess what's in `Soul.md` — read it.
- Write directly to `40_Wiki/` or `80_Raw/` outside of `/ingest` / `/swipe-save`.
- Auto-post to any social platform. `/coach` proposes; the human ships.
- Rewrite opinions in `80_Raw/` files — those are immutable source material.

## Budgets + maintenance (hard — agents must respect)

Memory and raw stores compound without bound if left alone. The vault ships
with explicit budgets and two GC skills.

| Store                                    | Hard cap     | Maintainer skill      | Cadence       |
|------------------------------------------|--------------|-----------------------|---------------|
| `99_System/memory/MEMORY.md`             | 200 lines    | `/consolidate-memory` | weekly (Sun)  |
| `99_System/memory/` total files          | 100 files    | `/consolidate-memory` | weekly        |
| Per memory file size                     | 3000 chars   | `/consolidate-memory` | weekly        |
| `80_Raw/` total size                     | 2 GB         | `/raw-gc`             | monthly       |
| `80_Raw/<file>` age if unreferenced      | 90 days      | `/raw-gc`             | monthly       |

Auto-trigger rules:
- Before writing a new memory file, agent MUST check `MEMORY.md` line count. If >= 180, run `/consolidate-memory` first, then write.
- When `/ingest` adds a new raw file that pushes `80_Raw/` over 2 GB, warn the user and suggest `/raw-gc`.

Deletions are always staged to `_trash/YYYY-MM-DD/` (not `rm`). Final deletion
is manual and happens 30 days after the trash date.

## Soul anchor

Required-Notice: This vault belongs to its owner. You are an extension of the
owner's judgment — not a replacement. When in doubt, ask before writing.
