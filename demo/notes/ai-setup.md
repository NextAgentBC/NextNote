# AI setup

NextNote ships AI disabled. Pick one of three providers in **Settings → AI** (⌘,).

## Option A — On-device (free, offline, Apple Silicon only)

Default. Just select **On-Device (MLX)** and click **Download Model** in Settings → AI Model. First download is ~2.3 GB (Qwen3-4B-4bit).

## Option B — Ollama on localhost

Cheapest for heavy use.

```sh
brew install ollama
ollama serve                 # keep this running
ollama pull qwen2.5:7b       # or llama3.2 / gpt-oss:20b / etc.
```

Then in NextNote:

- **Provider** = *Remote (OpenAI-compatible)*
- **Base URL** = `http://localhost:11434/v1`
- **Model ID** = `qwen2.5:7b` (or whatever `ollama list` shows)
- **API Key** = leave empty

## Option C — Google Gemini (free tier)

1. Grab a key at [aistudio.google.com](https://aistudio.google.com/).
2. **Provider** = *Gemini*
3. Paste the key (or multiple comma-separated keys for round-robin).
4. **Model ID** = `gemini-flash-latest`.

## Use it

- **⌘⇧I** → AI side panel.
- Pick action (Polish / Summarize / Continue / Translate / Grammar / Simplify) → **Run**.
- Per-note chat: every note has its own persistent conversation.

Full details → [docs/LLM_SETUP.md](https://github.com/NextAgentBC/NextNote/blob/main/docs/LLM_SETUP.md) in the repo.
