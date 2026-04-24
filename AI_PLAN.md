# nextNote — AI 综合路线 (Phase A–D)

> 融合四套方法论，给 nextNote 装上"有灵魂、会记忆、自增长"的 AI 工作台，**零自建 AI 代码**，全部通过 CLI (Claude Code / Gemini CLI) + vault 内 markdown 契约实现。
>
> 日期: 2026-04-24 ｜ 作者: Yao + Claude Opus 4.7

---

## 0. 致敬的四源

| 源 | 取什么 | 舍什么 |
|---|---|---|
| **OrbitOS** (MarsWang42) | 数字前缀文件夹 (00_Inbox → 99_System)、slash 工作流骨架 (`/start-my-day`, `/kickoff`, `/research`)、skills 作为 vault 内 markdown | 过度依赖 Obsidian canvas |
| **Karpathy LLM wiki** | `raw/` 不可变原料 + `wiki/` 编译知识、ingest/query/lint 三动作、**知识随时间复利**、link/citation 规则 | 仅 ingest 一次性动作，缺日常化闭环 |
| **Soul / auto-memory** | 身份文件 + 按类型切分记忆 (user/feedback/project/reference) + MEMORY.md 索引 | 现成 — 全借 |
| **Dan Koe canvas** | **策展语料库 + 对话语料** (YT/书贴进来，AI 聊那块料而非空谈) + swipe file + **scheduled coach prompt** + **guide → prompt** 压缩模式 | Eden 闭源 canvas，换 markdown 替代 |

---

## 1. 核心哲学

1. **Vault 是数据库。CLI 是运行时。nextNote 是外壳。** AI 逻辑不进 Swift 代码。
2. **人定 taste，AI 做苦力。** 反"全自动 agent army"，走"curator + coach"模式。
3. **知识复利 ≥ RAG。** ingest 时做合成，query 时查编译版，不每次重算关系。
4. **灵魂 = Identity + Memory + Episode 三层。** Soul.md 定人格，memory/ 存沉淀，10_Daily/ 做时间轴。
5. **所有自动化以明文 markdown 契约落地。** 换 CLI / 换模型 / 换 app 都不坏。

---

## 2. 统一 Vault 布局

```
<Vault Root>/
├── CLAUDE.md                  # 进入点，include Soul + 引用约定
├── GEMINI.md                  # 同上镜像（兼容 Gemini CLI）
│
├── 00_Inbox/                  # 未处理捕获，零格式门槛
├── 10_Daily/                  # YYYY-MM-DD.md 时间锚点（Episodic memory）
├── 20_Project/                # 活跃项目，frontmatter: status/phase
├── 30_Research/               # 结构化探究（中间产物）
├── 40_Wiki/                   # ← Karpathy 层：编译后的原子知识
│   ├── index.md               # 全局索引，按主题分组
│   ├── log.md                 # append-only ingest/query/lint 日志
│   └── <topic>/<concept>.md
├── 50_Resources/              # 长期参考（links, papers, tools）
├── 60_Canvas/                 # ← Koe 层：周级工作台
│   └── YYYY-Www/              # 每周一个，含 sources.md / outline.md / drafts.md
├── 70_Swipe/                  # ← Koe 层：高效结构范本，imitate-friendly
│   ├── posts/                 # 社交贴文 outliers
│   ├── titles/                # YT/文章标题库
│   └── hooks/                 # 开头钩子
├── 80_Raw/                    # ← Karpathy 层：不可变源料
│   └── <topic>/YYYY-MM-DD-slug.md   # 爬/贴原文 + frontmatter
├── 90_Plans/                  # 执行草案，完成后 → Archives/
│   └── Archives/
└── 99_System/
    ├── Soul.md                # ← Soul 层：人格、价值观、关系、语气 (<2k tokens)
    ├── memory/                # ← Soul 层：按类型切分
    │   ├── MEMORY.md          # 索引，一行一条
    │   ├── user_*.md
    │   ├── feedback_*.md
    │   ├── project_*.md
    │   └── reference_*.md
    ├── Prompts/               # 领域 persona (SE_Architect / Health_Nutrition / ...)
    ├── Templates/             # Daily / Project / Wiki / Inbox / Canvas
    ├── Bases/                 # 聚合视图定义
    └── .claude/skills/        # ← 工作流骨架：每个 skill 一目录 + SKILL.md
        ├── start-my-day/
        ├── kickoff/
        ├── research/
        ├── ingest/            # Karpathy ingest
        ├── query/             # Karpathy query
        ├── lint/              # Karpathy lint
        ├── weekly-canvas/     # Koe 周 canvas 生成
        ├── swipe-save/        # 粘 URL → 拉进 80_Raw + 归类 70_Swipe
        ├── coach/             # 定时教练 prompt
        ├── brand-strategy/    # Koe 三支柱第一支
        ├── content-engine/    # 第二支
        ├── offer-builder/     # 第三支
        ├── parse-knowledge/   # URL/PDF → atomic wiki
        └── archive/
```

> **合并要点:**
> - `80_Raw/` = Karpathy `raw/`，**所有外部源料的唯一写入口** (YT / Twitter / web / PDF 都先落这)
> - `40_Wiki/` = Karpathy `wiki/`，由 `/ingest` 合成，`/lint` 校验
> - `60_Canvas/` + `70_Swipe/` = Koe 层，**创作侧工作台**（与 Wiki 知识侧互补）
> - `10_Daily/` 与 OrbitOS 一致，是**时间轴，也是 episodic memory 检索锚**

---

## 3. CLAUDE.md 顶层契约（零代码落地灵魂）

```markdown
# nextNote Vault — Agent Briefing

## On every session start

1. Read `99_System/Soul.md` — apply tone, voice, values, relationships.
2. Read `99_System/memory/MEMORY.md` — scan index; load files whose `description` matches current topic.
3. Check today's daily note `10_Daily/$(date +%F).md`. If exists, treat as current working context.

## When user mentions a person / project / recurring concept
- Check `99_System/memory/` for existing record before asking.
- Update or write new memory file when learning non-obvious details.
- Follow the memory-type contract (user / feedback / project / reference).

## When user asks a factual or conceptual question
- Prefer `/query` (reads compiled `40_Wiki/`) over ad-hoc recall.
- Cite `40_Wiki/<topic>/<concept>.md` paths in answer.

## When user captures an idea / URL / quote
- Default action: `/swipe-save <target>` if it's an outlier structure, else drop to `00_Inbox/`.
- Never write directly to `40_Wiki/` — compilation is `/ingest`-only.

## Never
- Guess `Soul.md` content — read it.
- Write to `80_Raw/` except via `/ingest`.
- Auto-post to social — `/coach` proposes, human ships.

## Soul Anchor

Required-Notice: This vault belongs to <owner>. Agent is an extension of owner's judgment, not a replacement.
```

---

## 4. 三个灵魂层的具体落地

### 4.1 Identity — `99_System/Soul.md`
```markdown
---
type: soul
locked: true    # CI-checked; rejects edits outside <editable> blocks
---
# Soul

## Who am I
<2–4 句自我定义；身份、在意的事、回避的事>

## Voice
- 语气: <e.g. 直接、短句、偶尔犀利、不装>
- 反语气: <不要 X / 不要 Y>
- 语种: zh / en 混写，技术术语保留原文

## Relationships
- 妻子 <Name>: <关系要点，喜好忌讳>
- 合伙人 <Name>: <...>

## Anchors
- 长期目标: <...>
- 不做清单: <...>

<!-- editable:start -->
## Evolving notes
(agent 可在此块内追加观察)
<!-- editable:end -->
```

### 4.2 Memory — `99_System/memory/`
- 文件名编码类型: `user_role.md`, `feedback_testing.md`, `project_nextnote.md`, `reference_linear.md`
- 每文件 frontmatter: `name / description / type`
- MEMORY.md = 一行一指针: `- [Tutoring hours file format](reference_mason_invoice.md) — Mason monthly .xlsx schema`
- 保留 200 行以内（超出截断）

### 4.3 Episode — `10_Daily/YYYY-MM-DD.md`
- `/start-my-day` 生成，碰到"上周我说过啥" → agent grep `10_Daily/` 最近 N 天
- 含 `## AI Digest` 段，`/ai-newsletters` `/ai-products` 写入

---

## 5. 两条工作流动线

### 5.1 知识侧 (Karpathy loop) — 长期复利
```
URL / PDF / book         →  /swipe-save  →  80_Raw/<topic>/YYYY-MM-DD-slug.md
80_Raw 累积              →  /ingest      →  40_Wiki/<topic>/<concept>.md  (合成 + cascade update)
问答                     →  /query       →  读 index → 读相关 article → 引用回答
日常校验                 →  /lint        →  修 link / index / 孤儿页
```

### 5.2 创作侧 (Koe loop) — 周级产出
```
周一启动                 →  /weekly-canvas YYYY-Www
                            ↳ 建 60_Canvas/YYYY-Www/{sources,outline,drafts}.md
                            ↳ 扫 70_Swipe/ 提示模板
日常                     →  /coach (可由 CronCreate 每日 10am 触发)
                            ↳ 读 Soul + 当周 canvas + 最近 Swipe
                            ↳ 给一条今天该写的内容 prompt
周末                     →  /publish-ready
                            ↳ 从 drafts.md 挑 ready → 推 社交/Substack/博客
                            ↳ 归档当周 canvas
```

### 5.3 两侧交叉
- `/ingest` 时检测内容与当周 canvas 选题相关 → 自动在 canvas `sources.md` 加引用
- `/coach` 选题时查 `40_Wiki/` 与 `70_Swipe/` 做交叉激发
- `/start-my-day` 综合: carryover 未完 daily + active project + **当周 canvas 进度** + AI digest

---

## 6. nextNote app 端改动

| 改动 | Phase | 理由 |
|---|---|---|
| **Vault preset 「AI Soul」**: LibrarySetup 加一键按钮，往 Notes root 刷整套 §2 目录 + seed skills + Soul.md 模板 | A | 零代码价值验证 |
| **Daily Note 按钮** → 侧栏顶部，自动打开 `10_Daily/$(date +%F).md`（不存在则由 template 创建） | A | 已有基础，补锚点 UX |
| **Command palette (⌘K)** 扫 `99_System/.claude/skills/*/SKILL.md`，列 slash 清单 | B | 不用记命令 |
| **嵌入式 Terminal pane** (SwiftTerm, MIT)，cwd = vault root，底部 dock 与 AmbientBar 并排 | B | 把 CLI 变成一等公民 |
| **Capture 悬浮窗** (⌘⇧N)，贴 URL/文本即触发 `/swipe-save`，跑在后台 terminal | C | Koe swipe file 降摩擦 |
| **Canvas 视图**: `60_Canvas/YYYY-Www/` 渲染成双栏（sources | drafts），markdown 内嵌 YT 缩略图 + 拖拽 | C | Koe canvas 替代 Eden |
| **Schedule pane**: 调用 `schedule` skill / CronCreate，配 `/coach` 每日 9am，`/lint` 每周日晚 | C | Koe scheduled coach |
| **Soul lock CI**: commit hook 校验 `Soul.md` `<!-- editable -->` 外块未改 | D | 防人格漂移 |
| **逐步废弃自建 AI 栈** (AITextService / MLX / 多 provider): 留 MLX 做"离线快速 polish"降级，删 AIChatPanel 主功能 | D | CLI 全接管 |

---

## 7. 分期里程碑

### Phase A — 文件契约 (1-2 天，零 Swift 代码改动)
- [ ] 新建 `docs/vault-template/` 目录，写完整种子 vault（含 Soul / memory / skills 全套）
- [ ] 移植 OrbitOS 的 12 个 skills 到 `docs/vault-template/99_System/.claude/skills/`（改路径约定）
- [ ] 新增 `ingest / query / lint / weekly-canvas / swipe-save / coach / brand-strategy / content-engine / offer-builder` 9 个 skill 定义
- [ ] 在 [LibrarySetup.swift](nextNote/Views/LibrarySetupView.swift) 加 "Use AI Soul Preset" 按钮，按钮动作 = copy `docs/vault-template/` 到用户选的 Notes root
- [ ] 写 USER_GUIDE 新章节「AI workflow via CLI」
- 验收: 用户装 Claude Code，在 vault 目录跑 `claude` 即可用全部 slash workflow

### Phase B — Terminal 一等公民 (3-5 天)
- [ ] SPM 加 SwiftTerm 依赖
- [ ] 新增 `TerminalPane.swift`，cwd = `vault.root`，与 AmbientBar 同级 dock
- [ ] `AppState.showTerminal: Bool` + `⌘⇧T` 切换
- [ ] Command palette `⌘K`: 扫 `99_System/.claude/skills/*/SKILL.md`，回车 = 在 terminal 跑 `claude -p "/skill-name"`
- [ ] 拖拽文件进 terminal → 自动补路径
- 验收: 用户完全不用离开 nextNote 就能跑全部 AI 工作流

### Phase C — 创作侧 UX (1 周)
- [ ] Capture HUD (`⌘⇧N`)，贴 URL/文本 → 后台 `/swipe-save`，菜单栏图标转圈
- [ ] Canvas 视图: `60_Canvas/YYYY-Www/` 双栏 (sources | drafts)，支持 `![[80_Raw/...]]` 预览
- [ ] Schedule pane UI，含预设模板 (`/coach` 每日 9am, `/lint` 每周)
- [ ] Daily note 快捷键 + 模板变量 (`{{yesterday_carryover}}`, `{{active_projects}}`)
- 验收: 一周跑下来，60_Canvas/YYYY-Www/ 完整生成，有草稿、有 swipe、有 ingest 产出

### Phase D — 砍自建 AI + 人格硬化 (2 周)
- [ ] **工具栏 🧠 脑图标改行**: 现在点击开 `AIChatPanel` (本地 MLX 自建 chat)。改为触发 `appState.showCommandPalette.toggle()` — 与 ⌘K 同行为。图标保留但变成"AI 入口" = palette
- [ ] **AIChatPanel 降级 opt-in**: 默认关闭。Settings → Advanced 里有 toggle "启用经典 AI Chat (已废弃)" — 默认关。开启后 brain 图标长按或右键才显示。
- [ ] 删除 `AITextService` 多数动作；仅保留 polish / translate 作为"无网降级"工具（菜单栏 Tools 子菜单）。AIActionPanel 整体退役。
- [ ] MLX 模型下载改为可选 (Settings → Advanced → AI → "下载本地模型")，首启流程完全不触发
- [ ] `showMediaLibrary` 式残余 state 清理：AppState 里 `showAIPanel` 字段迁移/删除
- [ ] git pre-commit hook: 校验 `Soul.md` 的 `<!-- editable:start -->` 块外内容未改
- [ ] `consolidate-memory` skill 挂 Schedule (每周日 22:00)
- 验收:
  - nextNote bundle 体积 ≤ 50% 当前 (MLX 依赖去除后)
  - 首启 wizard 不提 AI 模型下载
  - 🧠 图标点击 = 开 palette，不再弹 "Model not loaded" 提示
  - 经典 AIChatPanel 默认不可达，仅设置里能重开

---

## 8. Dan Koe 模式在 nextNote 的具象

| Koe 做法 | nextNote 落地 |
|---|---|
| 周 canvas 粘 YT + prompt + AI chat | `60_Canvas/YYYY-Www/`, `/ingest <YT url>` 自动下载转写落 `80_Raw/` |
| 策展专家语料再对话 | `Prompts/SE_Architect.md` 等 persona + `/ingest` 专家 YT/博客 → `40_Wiki/` |
| guide → prompt 压缩 | `/parse-knowledge <source>` 产 `40_Wiki/` 页 + `99_System/Prompts/` 衍生 prompt |
| swipe file | `70_Swipe/{posts,titles,hooks}/`, `/swipe-save` 自动归类 |
| scheduled coach | CronCreate + `/coach` skill |
| brand/content/offer 三支柱 | 三个 skill (`/brand-strategy`, `/content-engine`, `/offer-builder`)，产出落 `20_Project/Personal-Brand/` |

---

## 9. 风险 / 开放问题

- **CLI 依赖门槛**: 用户要先装 Claude Code / Gemini CLI。缓解: LibrarySetup 检测缺失时显示 `brew install` hint（同 yt-dlp 模式）
- **多设备同步**: vault 走 iCloud/Dropbox/git，memory 文件会冲突。建议: `99_System/memory/` 加 git，其他按现状
- **人格漂移**: 用户改 Soul.md 不自觉稀释。Phase D lock 块 + 月度 `consolidate-memory` 缓解
- **80_Raw 膨胀**: YT 转写累积几 GB。Phase C 加 `/raw-gc` 按 90 天未引用清
- **Skills 版本**: 种子一次后用户改了，nextNote 升级如何合并？方案: skills 单独 `.nextnote-managed` 标签，有该标签的才覆盖
- **收费模式**: PolyForm NC 限制商用。企业/团队用 nextNote + AI 工作流需付费，企业版提供托管 Schedule、团队 memory 共享、Soul 中心管控 — 这跟 0.1.4 的商业保留一致
- **隐私**: Soul + memory 明文。若用户担心，Phase D 可加 `age` / `gpg` 加密 wrapper（`.soul-lock/` 目录）

---

## 10. 先做什么 (TL;DR)

1. **今天**: 建 `docs/vault-template/` 骨架 + 写 Soul.md / MEMORY.md / CLAUDE.md 种子
2. **本周**: 移植 + 新写 21 个 skills 到模板里
3. **下周**: LibrarySetup 加 preset 按钮，Phase A 发布 0.1.5
4. **两周后**: SwiftTerm 集成，Phase B 发布 0.2.0
5. **月底**: Canvas + Capture + Schedule 全打通，Phase C 发布 0.3.0

— 每个 phase 是独立可发布增量，失败可回滚到上一 phase。
