# nextNote — 整合方案与路线图

> 把 **PureText**（Markdown 编辑器 + MLX 本地大模型）和 **VoiceInput**（按 Fn 全局语音输入）整合成一个以 Markdown 为主、所见即所得、内置语音听写、能打开常见文档、本地持久化的笔记应用。
>
> 文档日期：2026-04-21 ｜ 作者：Claude + Yao

---

## 1. 现状盘点

### PureText（/mnt/PureText）
Swift + SwiftUI，**macOS 14+ / iOS 17+ 双平台**，~1500 行代码，24 个 Swift 文件。

有用的东西可以直接拿过来：

- **原生文本编辑层** — `NSTextView` / `UITextView` 的 `UIViewRepresentable` 封装（`Views/Editor/EditorView.swift`），带字号 / 行距 / 自动换行的偏好绑定。这是我们做 WYSIWYG 的地基。
- **文件导入** — `.fileImporter` modifier，支持 .md / .txt / .csv / .json / .html / .yaml / .toml / .xml / .swift / .py / .js / .ts / .go / .rs / .sh（`Models/FileType.swift`）。
- **AI 服务层（已重构完 Phase 1）** — 抽象的 `LLMProvider` 协议，两个实现：`MLXProvider`（本地 Apple Silicon 推理）和 `RemoteOpenAIProvider`（任何 OpenAI-compatible 端点：Ollama / vLLM / LM Studio / 自建网关）。封装好的 `AITextService` 已经提供：润色、摘要、续写、翻译、语法检查、分类打标签。
- **SwiftData 持久化** — `TextDocument` 模型（UUID + 内容 + tags + category + isFavorite + iCloudSynced 标志），自动保存已跑通。
- **基础分屏预览** — `WKWebView` 版 Markdown 预览（`MarkdownPreviewView.swift`），支持图片 URL（本地 + 远程）。

有用但需要重写的：

- **搜索是坏的** — UI 摆在那里，`findNext/Previous` 根本没动光标（REFACTOR_PROPOSAL.md 已列为问题 1）。
- **ContentView 过胖** — 582 行上帝视图，macOS / iOS 的 AI 面板几乎 100% 重复代码。
- **Markdown 渲染是正则涂色**，不是真 WYSIWYG，内联媒体未支持。
- **`DocumentVersion`、Speech.framework 授权、`AIService` 老单例** — 都是死代码。
- **拖拽图片 / 视频** — 零支持。
- **iOS 的 AppIntents、Share Extension** — 都没搭。

### VoiceInput（/mnt/VoiceInput）
Swift，**macOS 14+ 单平台菜单栏 app**，另有一个独立的 iOS Keyboard Extension。

语音部分是做得很完整的：

- **`STTEngine` 协议**（`Core/STTEngine.swift`，8 行）— 干净的抽象，`startRecording` / `stopRecording` 就两个方法。
- **三个引擎**：
  - `AppleSpeechEngine` — Apple Speech.framework，离线免费，带 contextualStrings（个性化词汇）。
  - `CloudSTTEngine` — multipart-form-data POST 到自建 STT 服务，Bearer token，3 次指数退避重试，16kHz WAV 重采样。
  - `WhisperEngine` — 目前是 stub，抛 `noInputDevice`。
- **`TextPostProcessor`** — URL / 域名归一化 + 个人词典后处理（~300 行，JSON 存储）。
- **`VocabularyDB`** — SQLite 词表（original / corrected / frequency / confidence），会自动从 AI 修改和用户手改中学习，剪掉可疑多行条目。
- **`LLMCache`** — SHA256 键的 raw → polished 缓存（SQLite），命中/拒绝计数。
- **`SessionStore`** — 会话历史（sessions / entries / agent_runs），524 行，可选。

扔掉的部分（菜单栏 app 专属，笔记 app 用不上）：

- `GlobalHotkey.swift` — CGEventTap 监听 Fn 键 + 辅助功能权限流程。
- `PreSendController` — 粘贴后自动敲 Enter 的倒计时调度（聊天场景用的，笔记无意义）。
- `InputSession` — 和全局快捷键深度绑定的录音编排。
- `FloatingPanel` / `SettingsWindow` / `SessionsWindow` — 菜单栏 UI。
- iOS 的 `Keyboard/KeyboardRecorder.swift` 用的是 AVAudioRecorder 文件路径（键盘扩展沙箱限制），**和 macOS 零代码共享**。

---

## 2. MarkItDown — 你提到的那个 skill

找到了。这是 **Microsoft 开源的 [markitdown](https://github.com/microsoft/markitdown)**（Python，25k+ stars），把 PDF / DOCX / XLSX / PPTX / HTML / CSV / JSON / EPUB / 图片（OCR）/ 音频（转录）统一转成 Markdown。目前**只有 Python 实现**，没有 Swift 原生版。社区有[若干 Claude skill 包装](https://gist.github.com/intellectronica/7c76818d79851fa8c33a6f7b0420bccb)，基本都是调 `uvx markitdown <file>`。

把它塞进一个 macOS 原生 app 有三条路：

| 方案 | 好处 | 坏处 |
|---|---|---|
| **A. 打包 Python 运行时** | 零依赖，用户点开即用 | App 体积 +100MB，沙箱签名麻烦 |
| **B. 要求用户装 `uv` + shell 调用** | 体积小，易更新 | 用户需要装环境，对非开发者不友好 |
| **C. 原生 Swift 逐格式实现** | 最干净，完全离线，沙箱无忧 | 工作量大；PDF 靠 PDFKit 还行，DOCX/XLSX/PPTX 要解 ZIP + OOXML |
| **D. 混合：原生做 PDF + 图片 OCR（Apple Vision），其他格式用 MarkItDown** | 日常文档（PDF）零依赖，Office 格式可选装 | 需要把 B 做成"可选增强" |

**我的推荐是 D**：PDF（PDFKit）+ TXT/MD（直接读）+ 图片 OCR（Apple Vision，已经在 Apple 系统里）先做原生；DOCX / XLSX / PPTX 先做 `uvx markitdown` 的 shell 后端，给用户一个 "安装增强支持" 的按钮，在 app 里用 `uv tool install markitdown` 一键装好。

---

## 3. 整合架构提议

先给结论，再讲理由。

### 3.1 起点选择

**不从零开始，而是 fork PureText 改名为 nextNote**，把 VoiceInput 的语音子系统抽成一个内部 Swift Package 塞进来。原因：

- PureText 已经搭好了双平台 SwiftUI 骨架、文件导入、偏好系统、MLX / Remote LLM 抽象、SwiftData schema，这些重新搭至少一周。
- PureText 的痛点（God View、搜索坏掉、无 WYSIWYG、无媒体）都是**可控的重构工作**，不是架构性地雷。
- VoiceInput 的核心价值在 `STTEngine` + 三个引擎 + `VocabularyDB` + `TextPostProcessor` + `LLMCache`，这些完全是可独立 lift 的纯逻辑层。

### 3.2 目标项目结构

```
nextNote/
├── project.yml                            # xcodegen 配置（沿用 PureText）
├── nextNote/
│   ├── App/
│   │   ├── nextNoteApp.swift              # @main 入口
│   │   └── AppState.swift                 # 从 PureText 搬过来
│   ├── Models/
│   │   ├── Note.swift                     # ⇐ 替换 TextDocument，加 frontmatter + attachments
│   │   ├── Attachment.swift               # 新：图片 / 视频 / 链接附件模型
│   │   ├── UserPreferences.swift          # 合并 PureText + VoiceInput 的 AppSettings
│   │   └── FileType.swift
│   ├── Views/
│   │   ├── ContentView.swift              # 精简版，拆成子视图
│   │   ├── Editor/
│   │   │   ├── WysiwygEditorView.swift    # 新：WebView + Milkdown / Lexical
│   │   │   └── VoiceDictationButton.swift # 新：按住说话组件
│   │   ├── Sidebar/
│   │   │   ├── NoteList.swift
│   │   │   └── CategoryTree.swift         # 新：分类树
│   │   └── Settings/                      # 合并两家的设置
│   ├── Services/
│   │   ├── AI/                            # 直接搬 PureText 的
│   │   ├── Import/
│   │   │   ├── MarkItDownBridge.swift     # 调用 uvx markitdown（可选）
│   │   │   ├── PDFImporter.swift          # PDFKit 原生
│   │   │   └── OCRImporter.swift          # Apple Vision 原生
│   │   └── Storage/
│   │       ├── NoteStore.swift            # SwiftData 封装
│   │       └── AttachmentStore.swift      # 文件系统 + 数据库索引
│   └── Packages/
│       └── SpeechToText/                   # 独立 SPM，从 VoiceInput 抽出来
│           ├── STTEngine.swift
│           ├── AppleSpeechEngine.swift
│           ├── CloudSTTEngine.swift
│           ├── WhisperEngine.swift
│           ├── TextPostProcessor.swift
│           ├── VocabularyDB.swift
│           └── LLMCache.swift
└── Resources/
```

`SpeechToText` 做成 Swift Package 的好处：既能给 nextNote 主 app 用（按住说话的按钮），将来要保留 VoiceInput 那套全局 Fn 热键也能复用。

### 3.3 编辑器核心：WYSIWYG 怎么做

你要的"拖拽图片、视频、所见即所得、md 为主"，**PureText 现在的正则涂色 + 分屏预览达不到**。两条路：

- **路径 1（JS 编辑器 + WKWebView）**：用 [Milkdown](https://milkdown.dev/)（基于 ProseMirror）或 Lexical 加载进 WebView，md 导入导出 + 真 WYSIWYG + 图片 / 视频节点原生支持。**优点**：生态成熟，富文本 + md 双向映射开箱；**缺点**：和原生 NSTextView 世界隔一层，光标 / 快捷键 / 文件拖放要走 JS 桥。
- **路径 2（NSTextView + TextKit 2 + NSTextAttachment）**：完全原生，`NSTextAttachment` 渲染图片 / 视频，自己写 md ↔ 属性串 的双向转换。**优点**：性能最好、原生操控感；**缺点**：是一个**月级别**的工程，要处理行内块、嵌套列表、代码块、表格的复杂交互。

**推荐路径 1**，因为：语音听写要的是"按住按钮，文字插进光标处"，这个用 JS 编辑器的 `insertText` API 就行；拖拽图片直接监听 `ondrop`；本地文件预览用 `file://` + content security policy。**PureText 的 `MarkdownPreviewView.swift` 已经是 WKWebView 架子，改造成双向编辑器门槛比从零做 TextKit WYSIWYG 低得多。**

### 3.4 语音听写集成方式

两种模式，在设置里用开关选：

- **模式 A（默认）— 应用内按钮 / 快捷键**：编辑器工具栏 + 全局菜单栏项上一个 🎤 按钮；按住（长按或按住快捷键如 ⌥⌘Space）开始录音，松开结束，转录文字直接插在光标处。零粘贴板、零合成 Cmd+V。
- **模式 B（可选）— 沿用 VoiceInput 全局 Fn 热键**：保留 VoiceInput 原来的 CGEventTap，但只要 nextNote 是前台窗口就发到编辑器；其他 app 前台时不工作（避免和原 VoiceInput.app 冲突）。

模式 A 用到的组件：`AppleSpeechEngine` 或 `CloudSTTEngine`（用户可选）+ `TextPostProcessor`（URL / 词典修正）+ `VocabularyDB`（学习个人词汇）+ `LLMCache`（LLM 润色缓存，可选）。**不需要** `GlobalHotkey` / `PreSendController` / `InputSession`。

### 3.5 本地数据库 schema

SwiftData 应付得了：

```swift
@Model class Note {
    var id: UUID
    var title: String
    var body: String              // Markdown 原文
    var frontmatter: [String: String]  // yaml front-matter 缓存
    var category: String?
    var tags: [String]
    var attachments: [Attachment] // relationship
    var links: [NoteLink]         // relationship, 用户贴的 URL
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var sourceURL: URL?           // 如果是从文件导入的
}

@Model class Attachment {
    var id: UUID
    var type: AttachmentType      // image / video / audio / file
    var localPath: URL            // 存在 ~/Library/Containers/.../Attachments/
    var remoteURL: URL?
    var sha256: String            // 去重用
    var createdAt: Date
}

@Model class NoteLink {
    var id: UUID
    var url: URL
    var title: String?
    var favicon: Data?
    var excerpt: String?
    var capturedAt: Date
}
```

**分类树**（你说的"按分类命名"）：用 `category` 字段 + "/" 分隔表示路径（`工作/项目A/周报`），侧栏用树形渲染。不做多级关系表，保留简单性。

**文件名约定**：notes 按 `{YYYY-MM-DD}-{slug}.md` 落盘到用户选定的笔记目录（非沙箱内部，用 security-scoped bookmark 访问），SwiftData 只存元数据 + 引用，真正的正文跟着 md 文件走。这样 iCloud Drive / Dropbox / Obsidian 任何目录都能直接用。

---

## 4. 路线图（建议分 5 个阶段）

| 阶段 | 主题 | 交付 | 预计时长 |
|---|---|---|---|
| **P0 — 起盘** | fork PureText 改名 nextNote，抽 SpeechToText 成 SPM | 能编译，菜单栏有 🎤，编辑器里按住能听写 | 2–3 天 |
| **P1 — WYSIWYG** | WKWebView 里集成 Milkdown，md ↔ HTML 双向；拖拽图片 / 视频；本地 `file://` 渲染 | 打开 .md 文件看到原生样式、拖图进去即刻显示 | 1–2 周 |
| **P2 — 文档导入** | PDFKit + Vision OCR 原生 importer；MarkItDownBridge（可选）；导入后存到 Note 表 | 能打开 PDF / DOCX / PPTX / 图片（OCR）→ md | 1 周 |
| **P3 — 组织** | 分类树、标签、链接收藏（粘 URL 自动抓 title/favicon/excerpt）、本地文件夹同步 | 侧栏分类、标签筛选、剪藏 URL 入库 | 1 周 |
| **P4 — 打磨** | 修 PureText 那堆已知 bug（搜索、snippet、ContentView 拆分、死代码清理）、加测试、iOS 版本 | 1.0 可发布 | 1–2 周 |

**最小可用版本（MVP = P0 + P1 + P2）** 大约 3 周，足够你日常用来替代 PureText 和 VoiceInput。

---

## 5. 锁定的决定（2026-04-21）

| # | 决定 | 选中 |
|---|---|---|
| 1 | 起点 | **Fork PureText** 改名 nextNote |
| 2 | 平台 | **macOS only**（v1；iOS 代码保留在仓库但不进 build target） |
| 3 | WYSIWYG | **WKWebView + Milkdown** |
| 4 | 文档导入 | **原生（PDFKit + Apple Vision）+ MarkItDown 可选**（`uvx markitdown` shell 后端，app 里一键装） |
| 5 | 语音模式 | **应用内按钮 + 前台快捷键**（不接管全局 Fn 键；原 VoiceInput.app 不冲突） |
| 6 | 笔记存储 | **用户选定文件夹，落盘 .md**，SwiftData 只存元数据 + 附件索引 |

---

## 6. 下一步

告诉我上面 6 个决定里你倾向的选项（或者说"按你推荐的来"），我就开始做 P0：

1. 建 `nextNote/project.yml`，bundle id `com.nextnote.app`
2. 把 PureText 的 Swift 源码拷进来，改名、清掉 dead code（DocumentVersion、Speech 授权里没用的）
3. 把 VoiceInput 的 `STTEngine` / `AppleSpeechEngine` / `CloudSTTEngine` / `WhisperEngine` / `TextPostProcessor` / `VocabularyDB` / `LLMCache` 抽成 `SpeechToText` SPM
4. 编辑器工具栏加 🎤 按钮，按住录音、松开插入光标处 — 这一步就能让 nextNote 有雏形了

---

## 7. 路线图 v2（2026-04-24 起，living doc）

> §1–§6 是项目起源的整合方案（PureText + VoiceInput → nextNote），作为档案保留。§7 起是 0.1.2 之后的前瞻路线图，会不停添加 / 修正，每次大 feature 落地就把对应条目从这里移到 `CHANGELOG.md` 的 Released 区块。

### 7.1 总体方向

五条可并行的 track：

| Track | 主题 | 优先级 | 目标版本 |
|---|---|---|---|
| **A. 媒体创作** | 图片编辑 / 音频编辑 / 录屏 | 高（补齐"从素材到笔记"闭环） | v0.2 |
| **B. AI provider 扩展** | Claude / GPT / 国产模型原生接入 | 中 | v0.2 |
| **C. 增强 AI 用例** | 长上下文总结 / 迭代改写 / 语义搜索 / Auto-link / Notebook RAG | 中（依赖 Track B 的强模型） | v0.3 |
| **D. 同步** | iCloud Sync 一键迁移 | 低（现在放 iCloud Drive 就能同步） | v0.3+ |
| **E. UX 持续优化** | `UX_AUDIT.md` 里的 P1/P2/P3 | 持续 | 每个 release |

---

### 7.2 Track A — 媒体创作

#### A1. 🖼️ 图片编辑

**MVP 范围**

- 裁剪、旋转（90° / 任意角）、水平/垂直翻转
- 亮度 / 对比度 / 饱和度（Core Image `CIColorControls`）
- 简单标注：箭头、矩形、文字、马克笔（PencilKit 或 `NSBezierPath` 叠加层）
- 一键导出 `<原文件>-edit.png`，原图保留

**入口**

- 素材库预览 sheet 里加铅笔按钮（和视频的剪刀对称）
- 素材库 / Finder 图片右键 → "Edit Image…"

**实现路径**

- 新建 `Views/Assets/ImageEditorView.swift`
- 调色用 Core Image filter graph（非破坏性，状态是几个数值参数）
- 标注用 SwiftUI `Canvas` 层叠在图片上，用户笔画存成 `[Stroke]` 数组
- 可选："保存一份旁路 `.nxedit.json` 记录操作栈" → 日后二次编辑
- 最终导出走 `CIContext.createCGImage` → PNG/JPG

**非目标（留给未来）**

- 图层 / 蒙版 / 混合模式
- RAW / HDR
- AI 抠图、inpainting、生图（归到 Track C）

#### A2. 🎚️ 音频编辑

**MVP**

- Trim（波形上拖两端标记）
- 渐入 / 渐出（两侧各拖一个滑块）
- 音量标准化（LUFS 目标 -14，`AVAudioUnitEQ` + 简单峰值检测）
- 变速（保持音调，`AVAudioUnitTimePitch`）

**入口**

- Media Library / Asset Library 里音频预览界面，和视频的 Trim 按钮对称

**实现**

- 组合层：`AVMutableComposition` + `AVAudioMix`
- 波形绘制：`AVAssetReader` 抽 PCM → 按屏幕宽度下采样成 `(min, max)` bucket → `Canvas` 画垂直线。每个 track ≤ 屏宽个采样，绘制 <16 ms
- 导出：`AVAssetExportSession` → m4a (AAC) 或 wav
- 文件命名同图片：`<原文件>-edit.m4a`

**进阶（可选，单独 MR）**

- 降噪：RNNoise 本地模型（有开源 Swift 包装）或谱减法
- 多段编辑（cut-paste）需要把单轨扩成 `AVMutableCompositionTrack` 时间线

#### A3. 📹 录屏

**方案**：ScreenCaptureKit（macOS 12.3+，苹果官方推荐，低 CPU）

**UI**

- 菜单栏图标（或主窗菜单） → 三个模式：🖥️ 全屏 / 🪟 选窗口 / ▭ 选区域
- 可选 🎤 麦克风 + 🔊 系统声
- 录制中：屏幕角落一个 Stop 小按钮（不是整个 HUD），不打扰录制内容
- 快捷键：⌘⇧5（和系统截屏一致的直觉），或自定义

**输出**

- H.264 mp4，写进 Media 根目录或 Assets（设置里选）
- 录完自动弹 Video Vibe 窗预览
- 可选 toggle："录完直接跳进 Trim 编辑器" → 无缝衔接 A1

**权限**

- macOS 15+ 的 Screen Recording TCC 授权流程，首次录制前弹引导 UI（说明为什么要、点哪里开）

**扩展点**

- 录制核心抽成 `ScreenRecordingService`，将来加 "GIF 导出" / "自动字幕"（走 Apple Speech 或 Whisper）只需上层接

---

### 7.3 Track B — 多模型 provider

#### B1. Preset dropdown（最低投入、最高回报）

**问题**：国产模型大部分已经兼容 OpenAI API 格式，现有 Remote provider 其实已经能用。但用户要自己查 baseURL 和 model name，门槛太高。

**方案**：加一个预设选择器

- 新建 `Models/ProviderPreset.swift`：

  ```swift
  struct ProviderPreset: Identifiable {
      let id: String              // "deepseek"
      let displayName: String     // "DeepSeek"
      let baseURL: String         // "https://api.deepseek.com/v1"
      let defaultModel: String    // "deepseek-chat"
      let apiKeyHelpURL: URL      // 官方申请 key 的页面
      let requiresThinkingToggle: Bool
      let contextWindow: Int      // 供 UI 展示
      let notes: String?
  }
  ```

- Settings → AI 的 Remote provider 下加 **Preset** dropdown，选了之后自动填 baseURL / model / thinking toggle
- 内置预设：DeepSeek、通义千问 Qwen、Kimi、豆包、智谱 GLM、OpenAI、xAI Grok、Mistral、Groq、自定义

**工作量**：半天

#### B2. Claude 原生 provider

**为什么原生**：Claude 的 Messages API 和 OpenAI Chat Completions 结构不同；prompt caching / tool use / extended thinking 都必须走原生才能开。将来 Agent SDK / MCP 也是原生协议。

**方案**

- `Services/AI/AnthropicProvider.swift` conform `LLMProvider`
- `URLSession.bytes(for:)` 做流式，自己解 SSE（~150 行）
- Key 放 Keychain
- 预设：`claude-opus-4-7` / `claude-sonnet-4-6` / `claude-haiku-4-5-20251001`
- Prompt caching 在构造请求时对 system prompt + 长上下文加 `cache_control: { type: "ephemeral" }`

**不引第三方**：官方 Swift SDK 不成熟，手写 ~200 行更干净。

#### B3. OpenAI 原生 provider

同样原因 —— 原生解锁 structured outputs / function calling / `reasoning_effort`。**和 B2 共用一套 SSE 解析工具**。

#### B4. 成本可见化

- `LLMProvider` 协议加：

  ```swift
  struct Usage {
      let inputTokens: Int
      let outputTokens: Int
      let cachedInputTokens: Int?
      let estimatedCostUSD: Decimal
  }
  var lastUsage: Usage? { get }
  ```

- AI 面板右上角小字显示 "≈ $0.003"
- Settings → AI → 本月累计 / 上月累计 + 按 provider 拆分

---

### 7.4 Track C — 增强 AI 用例

> 这些功能弱模型做不好（4B MLX 会翻车）。实现时给 `LLMProvider` 加 `capabilities: Set<Capability>` 位（`.longContext` / `.toolUse` / `.reasoning` / `.jsonMode`），用户选了不匹配能力的 provider 时在功能入口显示 "需要更强模型" 的 banner。

#### C1. 长上下文总结

- 整个文件夹 / 整本笔记的 brief
- Map-reduce：
  1. **Map** — 对每条 note 用 `summarize(note)` 出要点（缓存 key = note 内容 hash）
  2. **Reduce** — 把所有要点拼起来让模型做 meta-summary（缓存 key = 所有 map 结果的 hash）
- 缓存命中率会很高：只要 note 没改，map 结果复用；只要 folder 内 note 集合不变，reduce 也复用

#### C2. 迭代改写（Polish v2）

- 流程：`generate → self-critique → revise`
  1. 第一次 polish → `v1`
  2. 让模型挑 `v1` 的 3 个最大问题（critique）
  3. 按 critique 重写 → `v2`
- UI：Polish 按钮旁加 **🔁 Iterate** toggle，开了就跑 3 步版本
- 成本会是单次 polish 的 ~3 倍，B4 的成本可见化在这里尤其重要

#### C3. 语义搜索

**栈**

- Embedding：Voyage-3-large（云）/ `text-embedding-3-small`（OpenAI）/ `text-embedding-004`（Gemini）/ BGE-M3（本地 via llama.cpp）
- 向量库：SQLite + [`sqlite-vec`](https://github.com/asg017/sqlite-vec) 扩展。不引 Chroma / Qdrant，保留零后台服务
- 索引策略：FSEventStream 监听 `<notes>/`，mtime 变了才 re-embed 该文件；按段落 chunk（~500 token 重叠 50）

**UI**

- ⌘⇧F 打开语义搜索框（和普通 ⌘F 关键字搜索并存）
- 结果带相关度 0–1 + 前后文片段高亮

#### C4. Auto-tag / Auto-link

**触发**：笔记保存后 debounce 5s，后台异步跑

**做法**

- 用 C3 的 embedding 取 top-20 候选相关笔记
- LLM 从 20 里挑 3 条最相关
- LLM 生成 1–5 个 tag
- 结果写回：
  - Tag → note 的 YAML front-matter
  - 相关笔记 → 笔记末尾的 `## Related` 小节（可整体关闭）

#### C5. Notebook Q&A（RAG）

- 前端：扩展 per-note chat 的 context toggle —— `Doc` / `Folder` / **`Notebook`**（新增）
- 后端：
  - 用户问题 → embedding
  - 从 vector db 取 top-k chunks（k=8）
  - 塞进 system prompt：`"Based on the following excerpts from the user's notes, answer [excerpts with source paths]"`
  - 输出要求 LLM 引用源笔记，格式 `> From journal/2026-04-12.md:`

---

### 7.5 Track D — 同步

#### D1. iCloud sync（主要解决两件事）

现在用户把 Notes root 指向 `~/Library/Mobile Documents/com~apple~CloudDocs/` 就能同步正文了。这个 Track 要补的是：

- **一键迁移 wizard**：现有 Notes root → 复制到 iCloud 子文件夹 → 切换 security-scoped bookmark
- **元数据同步**：SwiftData 层的 tags / favorites / chat 历史（这些不在 `.md` 里），走 CloudKit

**优先级低**因为：a) 正文同步用户已有土办法；b) SwiftData 的 CloudKit sync 在 iOS 17 / macOS 14 上还偶尔出问题。

---

### 7.6 Track E — UX 持续优化

参见 `UX_AUDIT.md`。按那份文档里的 P1/P2/P3 列表每个 release 消化 2–4 条，优先修用户反馈最多的。

新的 UX 问题发现后，直接加到 `UX_AUDIT.md` 相应 severity 下，**不用**在这里复述。

---

### 7.7 发布节奏（滚动规划）

| 版本 | 目标范围 | 预计时间线 |
|---|---|---|
| **v0.2** | A1（图片编辑）+ A2（音频编辑）+ B1（Preset）+ B2（Claude 原生）+ E 挑 3 条 P1 | ~1 个月 |
| **v0.3** | A3（录屏）+ B3（OpenAI 原生）+ B4（成本可视）+ C1（长上下文总结）+ C2（迭代改写） | ~2 个月 |
| **v0.4** | C3 + C4 + C5（RAG 全家桶） | ~3 个月 |
| **v0.5+** | D + 更多由社区反馈驱动 | 持续 |

> 时间是估算，不是承诺。实际节奏由用户反馈和遇到的技术风险调整。

---

## 8. 本文档的维护约定

- **§1–§6** — 项目起源档案（2026-04-21 整合方案），不动
- **§7 起** — living roadmap：
  1. 每次 feature 落地，把对应条目从计划里移到 `CHANGELOG.md` 的 Released 区块，并在这里打 ✅
  2. 新想法按 Track 追加到对应 §7.x 子节
  3. 优先级变化直接改 §7.1 表格里的 "优先级" 列
  4. 重大技术决定（例如"要不要加新的第三方依赖"）写成新表格，追加到 §5"锁定的决定"后面（不要改 §5 本身的表）
- **语言**：中文为主（和 §1–§6 一致），引用代码 / 类名 / API 保留英文原文

