# LLM Setup

NextNote talks to large language models through one of three providers. Pick whichever fits. All three feed the same features (polish, summarize, continue, translate, grammar, per-note chat, daily digest).

| | On-device (MLX) | OpenAI-compatible | Gemini |
|---|---|---|---|
| Where it runs | Your Mac | A server you run or rent | Google cloud |
| Cost | Free | Electricity / rental | Free tier + paid |
| Privacy | 100 % local | Whatever the server sees | Sent to Google |
| Apple Silicon needed | **Yes** | No | No |
| First-run download | ~2–4 GB | — | — |
| Offline | ✅ | LAN only | ❌ |

Change provider anytime in **Settings → AI**.

---

## 1 · On-device (MLX) — default

Works out of the box on Apple Silicon. First run downloads a quantized model from Hugging Face to `~/Library/Application Support/.../models/`.

Default model: `mlx-community/Qwen3-4B-4bit` (~2.3 GB).

- **Settings → AI** → *Provider* = **On-Device (MLX)**.
- **Settings → AI → Model** to pick / switch models (any `mlx-community/*` works).
- Download progress shows in the AI panel.

Gated models (Llama 3, Gemma, etc.) need a Hugging Face token. Paste it in **Settings → AI → Hugging Face Token**.

---

## 2 · OpenAI-compatible server

Any HTTP server that speaks the OpenAI `/v1/chat/completions` shape. Proven combinations:

### Ollama (easiest)

```sh
brew install ollama
ollama serve                           # leave this running
ollama pull qwen2.5:7b                 # or llama3.2:3b / gpt-oss:20b / etc.
```

In NextNote:

- **Settings → AI → Provider** = *Remote (OpenAI-compatible)*
- **Base URL** = `http://localhost:11434/v1`
- **Model ID** = `qwen2.5:7b` (whatever you pulled — run `ollama list` to check)
- **API Key** = leave empty

Ollama accepts HTTP on localhost. NextNote's `Info.plist` already exempts `localhost` from App Transport Security.

### LM Studio

1. Open LM Studio → *Server* tab → Start the server (default port 1234).
2. Base URL = `http://localhost:1234/v1`, Model ID = whatever LM Studio shows.

### vLLM / llama.cpp server / self-hosted

Whatever you're running, set:

- **Base URL** = `http(s)://<host>:<port>/v1`
- **Model ID** = the model identifier your server exposes
- **API Key** = if your server requires one

**Plain-HTTP to non-localhost hosts** (e.g. `http://192.168.1.10:11434` or a Tailscale IP like `http://100.x.x.x:11434`) needs an App Transport Security exemption. Edit `nextNote/Resources/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSExceptionDomains</key>
  <dict>
    <key>192.168.1.10</key>
    <dict>
      <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
    </dict>
  </dict>
</dict>
```

Rebuild. HTTPS endpoints (anything with `https://`) work without ATS changes.

---

## 3 · Google Gemini (free tier)

1. Go to [Google AI Studio](https://aistudio.google.com/) → *Get API key*.
2. **Settings → AI → Provider** = *Gemini*.
3. Paste the key. You can paste **multiple keys** separated by commas — NextNote rotates through them when one hits the per-minute quota, giving you effectively higher throughput on the free tier.
4. **Model ID** — Google rebrands these frequently; typical values today: `gemini-flash-latest`, `gemini-2.5-flash`, `gemini-3.0-flash-lite`. Check AI Studio for current names.

All Gemini calls go through an internal rate limiter + summary cache so free-tier quotas stick.

---

## Storage / Privacy notes

- API keys are stored in macOS **Keychain**, not plain-text config files.
- `Base URL` and `Model ID` live in `UserDefaults` (plain text, but local-only).
- Nothing leaves your Mac **unless** you picked Remote or Gemini. On-device is fully offline once the model is downloaded.

## Debugging

- Watch what's going on: `log stream --predicate 'process == "nextNote"'`.
- "AI model not downloaded" banner → **Settings → AI → Model** → *Download*.
- "Connection refused" → server isn't running at the Base URL you gave.
- "401 / 403" → bad / missing API key.
- First launch hang → macOS Keychain prompt queued somewhere — unlock via Keychain Access.app.

## Switching providers

Flip **Settings → AI → Provider** and NextNote rebuilds the underlying `LLMProvider` in place. Existing per-note chat transcripts stay (they're stored on disk), but tone / style may shift since the new model has different training.
