# nextNote AI Soul — Vault Template

Seed contents for a nextNote vault that runs the full AI Soul workflow via
Claude Code / Gemini CLI. No nextNote Swift code required to use any of this —
it's all markdown contract.

## What this is

An opinionated folder + skills layout that fuses:

- **OrbitOS** — digital-prefix folders, slash-workflow skeleton.
- **Karpathy LLM wiki** — `80_Raw/` immutable sources + `40_Wiki/` compiled knowledge + `/ingest` / `/query` / `/lint`.
- **Soul + auto-memory** — `Soul.md` identity + `memory/` typed facts + `MEMORY.md` index.
- **Dan Koe canvas** — `60_Canvas/YYYY-Www/` weekly work + `70_Swipe/` pattern library + `/coach` scheduled prompt.
- **Anthropic memory hygiene** — `/consolidate-memory` + `/raw-gc` with hard budgets to prevent long-term bloat.

## How to adopt

Option 1 — in nextNote (Phase A+):
- `Library → Use AI Soul Preset` — copies this directory into your Notes root.

Option 2 — manual:
```bash
cp -R docs/vault-template/ ~/my-vault/
cd ~/my-vault && claude
```

First session, Claude reads `CLAUDE.md` and applies the contract.

## First-week runbook

1. Fill in `99_System/Soul.md` — who you are, voice, pillars.
2. Run `/brand-strategy` once to establish pillars (≈ 30 min interview).
3. Run `/weekly-canvas` — sets up this week's Dan Koe canvas.
4. Next morning: `/start-my-day`.
5. Whenever you find something worth saving: `/swipe-save <url>` or `/ingest <url>`.
6. Sunday night: `/consolidate-memory` + `/lint`.

## Skill index

See `99_System/.claude/skills/*/SKILL.md`.

## Budgets (enforced)

| Store | Hard cap | Skill |
|---|---|---|
| `99_System/memory/MEMORY.md` | 200 lines | `/consolidate-memory` |
| `99_System/memory/` files | 100 | `/consolidate-memory` |
| `80_Raw/` size | 2 GB | `/raw-gc` |

Deletes stage to `_trash/YYYY-MM-DD/`. Final `rm` is always manual.
