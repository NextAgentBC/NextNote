import SwiftUI

@MainActor
final class UserPreferences: ObservableObject {
    static let shared = UserPreferences()

    // MARK: - Appearance
    @AppStorage("themeMode") var themeMode: String = "system"
    @AppStorage("fontName") var fontName: String = "SF Mono"
    @AppStorage("fontSize") var fontSize: Double = 16
    @AppStorage("lineSpacing") var lineSpacing: Double = 1.4
    @AppStorage("showLineNumbers") var showLineNumbers: Bool = true

    // MARK: - Editor
    @AppStorage("autoSaveInterval") var autoSaveInterval: Int = 30
    @AppStorage("autoIndent") var autoIndent: Bool = true
    @AppStorage("tabWidth") var tabWidth: Int = 4
    @AppStorage("wrapLines") var wrapLines: Bool = true

    // MARK: - Default format for new documents
    @AppStorage("defaultFileType") var defaultFileType: String = FileType.txt.rawValue

    // MARK: - AI
    @AppStorage("enableAI") var enableAI: Bool = true
    @AppStorage("preferredAILanguage") var preferredAILanguage: String = "zh-CN"
    @AppStorage("autoGrammarCheck") var autoGrammarCheck: Bool = false
    @AppStorage("hfToken") var hfToken: String = ""
    @AppStorage("aiModelId") var aiModelId: String = "mlx-community/Qwen3-4B-4bit"

    // MARK: - AI Provider (on-device vs remote vs gemini)
    @AppStorage("aiProviderType") var aiProviderType: String = AIProviderType.onDevice.rawValue
    /// Blank by default — open-source users point this at whatever
    /// OpenAI-compatible endpoint they run (Ollama http://localhost:11434/v1,
    /// LM Studio, vLLM, self-hosted, etc.). Configured in Settings → AI.
    @AppStorage("remoteBaseURL") var remoteBaseURL: String = ""
    /// Model ID that the remote server exposes (e.g. "llama3.2",
    /// "qwen2.5:7b", "gpt-oss:20b"). Empty until user fills it in.
    @AppStorage("remoteModelId") var remoteModelId: String = ""

    /// When true, send `chat_template_kwargs.enable_thinking=false` to Qwen-style
    /// models so they skip the reasoning stage and answer directly (faster).
    /// Set false for tasks where quality matters more than latency.
    @AppStorage("remoteDisableThinking") var remoteDisableThinking: Bool = true

    // MARK: - Gemini (Google AI Studio free tier — R4)
    // API key lives in Keychain, not here. Model id is opaque — Google
    // rebrands these frequently (flash / flash-lite / 2.5-flash / 3.0-flash-lite),
    // so we store it as a plain string the user can edit.
    @AppStorage("geminiModelId") var geminiModelId: String = "gemini-flash-latest"

    // MARK: - Sync
    @AppStorage("enableICloudSync") var enableICloudSync: Bool = false

    // MARK: - Vault (R0 redesign feature flag)
    // When false, app runs legacy flat SwiftData-backed document model.
    // When true, app runs new directory-backed vault model (R1+).
    // Default false until R2 migration lands and is verified on the user's data.
    @AppStorage("vaultMode") var vaultMode: Bool = true

    static let supportedLanguages: [(code: String, name: String)] = [
        ("zh-CN", "简体中文"),
        ("zh-TW", "繁體中文"),
        ("en-US", "English"),
        ("ja-JP", "日本語"),
        ("ko-KR", "한국어"),
    ]

    var editorFont: Font {
        .custom(fontName, size: fontSize)
    }

    private init() {}
}
