import SwiftUI
import Combine

/// Application-layer AI service.
/// Views observe this singleton for both model state and feature results.
/// The concrete LLMProvider (on-device MLX or remote Ollama) is swapped via `reconfigure()`.
@MainActor
final class AITextService: ObservableObject {

    static let shared = AITextService()

    // MARK: - Published state

    @Published var modelState: ModelState = .notDownloaded
    @Published var isProcessing: Bool = false
    @Published var tokensPerSecond: Double = 0

    // MARK: - Static catalog (delegated to manager)

    static var availableModels: [ModelOption] { AIModelManager.availableModels }

    // MARK: - Internal

    private let modelManager: AIModelManager
    private var provider: any LLMProvider
    private var modelStateSub: AnyCancellable?

    // Rate limiter + cache shared across all throttled providers so the
    // Gemini quota is honored regardless of how many parallel dashboards
    // are asking at once. The cache needs a vault root to live in, so it
    // stays nil until the user picks a vault.
    private let sharedLimiter = RateLimiter()
    private(set) var sharedCache: SummaryCache?

    private init() {
        self.modelManager = AIModelManager.shared
        // Default to on-device; reconfigure() will switch if prefs say remote/gemini.
        self.provider = MLXProvider(manager: AIModelManager.shared)
        subscribeToModelManager()
        reconfigure()
    }

    /// Call when the user picks a vault so we can put the summary cache
    /// inside it. Safe to call repeatedly.
    func bindVault(rootURL: URL) {
        sharedCache = SummaryCache(vaultRoot: rootURL)
        reconfigure()
    }

    // MARK: - Provider switching

    /// Call after the user changes the provider picker in Settings.
    func reconfigure() {
        let saved = UserPreferences.shared.aiProviderType
        switch AIProviderType(rawValue: saved) {
        case .remote:  applyRemoteProvider()
        case .gemini:  applyGeminiProvider()
        default:       applyMLXProvider()
        }
    }

    /// Current underlying provider. Used by dashboard/digest services that
    /// want to bypass the app-level polish methods and call raw generate().
    var currentProvider: any LLMProvider { provider }

    private func applyMLXProvider() {
        provider = MLXProvider(manager: modelManager)
        subscribeToModelManager()
    }

    private func applyRemoteProvider() {
        let prefs = UserPreferences.shared
        // Keychain lookups can block on securityd — hop off the main actor.
        Task.detached(priority: .userInitiated) {
            let apiKey = KeychainStore.get(.openai)
            await MainActor.run {
                var extraBody: [String: Any] = [:]
                if prefs.remoteDisableThinking {
                    extraBody["chat_template_kwargs"] = ["enable_thinking": false]
                }
                self.provider = RemoteOpenAIProvider(
                    baseURL: prefs.remoteBaseURL,
                    model: prefs.remoteModelId,
                    apiKey: apiKey,
                    extraBody: extraBody
                )
                self.modelStateSub = nil
                self.modelState = .ready
            }
        }
    }

    private func applyGeminiProvider() {
        // Off-main: Keychain can block on securityd.
        Task.detached(priority: .userInitiated) {
            let raw = KeychainStore.get(.gemini) ?? ""
            let keys = raw
                .split(whereSeparator: { $0 == "," || $0 == "\n" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            await MainActor.run {
                guard !keys.isEmpty else {
                    self.applyMLXProvider()
                    return
                }
                let model = UserPreferences.shared.geminiModelId
                let gemini = GeminiProvider(apiKeys: keys, model: model)
                self.provider = ThrottledCachedProvider(
                    inner: gemini,
                    limiter: self.sharedLimiter,
                    cache: self.sharedCache,
                    modelId: model
                )
                self.modelStateSub = nil
                self.modelState = .ready
            }
        }
    }

    private func subscribeToModelManager() {
        modelStateSub = modelManager.$modelState
            .sink { [weak self] state in
                self?.modelState = state
            }
    }

    // MARK: - Model lifecycle (MLX only; no-ops for remote)

    func downloadModel() async {
        await modelManager.downloadModel()
    }

    func deleteModel() {
        modelManager.deleteModel()
    }

    // MARK: - Test connection

    /// Returns a user-facing message: "Connected" or an error description.
    func testRemoteConnection() async -> String {
        do {
            try await provider.testConnection()
            return "Connected"
        } catch {
            return "Failed: \(error.localizedDescription)"
        }
    }

    // MARK: - AI Features

    func summarize(_ text: String, length: SummaryLength = .medium) async -> String {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let result = try await provider.generate(
                messages: [
                    LLMMessage(.system, "You are a precise text summarizer. Output only the summary, nothing else."),
                    LLMMessage(.user, "Summarize the following text in \(length.instruction):\n\n\(text)"),
                ],
                parameters: LLMParameters(maxTokens: 1024, temperature: 0.3)
            )
            tokensPerSecond = provider.lastTokensPerSecond
            return result
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    func polish(_ text: String, style: PolishStyle = .concise) async -> String {
        isProcessing = true
        defer { isProcessing = false }

        let styleInstruction: String
        switch style {
        case .formal:  styleInstruction = "Rewrite in a formal, professional tone. Maintain the original meaning."
        case .concise: styleInstruction = "Make the text more concise and clear. Remove redundancy. Maintain meaning."
        case .vivid:   styleInstruction = "Rewrite with more vivid, engaging language. Maintain the original meaning."
        }

        do {
            let result = try await provider.generate(
                messages: [
                    LLMMessage(.system, "You are a writing assistant. \(styleInstruction) Output only the polished text."),
                    LLMMessage(.user, text),
                ],
                parameters: LLMParameters(maxTokens: 2048, temperature: 0.4)
            )
            tokensPerSecond = provider.lastTokensPerSecond
            return result
        } catch {
            return text
        }
    }

    func continueWriting(_ text: String, maxTokens: Int = 200) async -> AsyncStream<String> {
        isProcessing = true

        let stream = provider.generateStream(
            messages: [
                LLMMessage(.system, "You are a writing assistant. Continue writing naturally from where the text ends. Match the existing tone and style. Output only the continuation."),
                LLMMessage(.user, "Continue this text:\n\n\(text)"),
            ],
            parameters: LLMParameters(maxTokens: maxTokens, temperature: 0.7)
        )

        return AsyncStream { continuation in
            Task { [weak self] in
                do {
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                } catch {
                    // Stream ended or errored — finish silently.
                }
                continuation.finish()
                await MainActor.run { self?.isProcessing = false }
            }
        }
    }

    func translate(_ text: String, to language: String) async -> String {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let result = try await provider.generate(
                messages: [
                    LLMMessage(.system, "You are a translator. Translate the given text to \(language). Output only the translation, nothing else."),
                    LLMMessage(.user, text),
                ],
                parameters: LLMParameters(maxTokens: 2048, temperature: 0.2)
            )
            tokensPerSecond = provider.lastTokensPerSecond
            return result
        } catch {
            return text
        }
    }

    func checkGrammar(_ text: String) async -> [GrammarSuggestion] {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let response = try await provider.generate(
                messages: [
                    LLMMessage(.system, """
                        You are a grammar checker. Find grammar errors in the text.
                        For each error, output one line in this exact format:
                        ORIGINAL|||SUGGESTION|||EXPLANATION
                        If no errors found, output: NO_ERRORS
                        """),
                    LLMMessage(.user, text),
                ],
                parameters: LLMParameters(maxTokens: 1024, temperature: 0.1)
            )
            tokensPerSecond = provider.lastTokensPerSecond

            if response.contains("NO_ERRORS") { return [] }

            return response.components(separatedBy: "\n").compactMap { line in
                let parts = line.components(separatedBy: "|||")
                guard parts.count == 3 else { return nil }
                let original    = parts[0].trimmingCharacters(in: .whitespaces)
                let suggestion  = parts[1].trimmingCharacters(in: .whitespaces)
                let explanation = parts[2].trimmingCharacters(in: .whitespaces)
                guard let range = text.range(of: original) else { return nil }
                return GrammarSuggestion(range: range, original: original,
                                         suggestion: suggestion, explanation: explanation)
            }
        } catch {
            return []
        }
    }

    func classifyAndTag(_ text: String) async -> (category: String?, tags: [String]) {
        do {
            let response = try await provider.generate(
                messages: [
                    LLMMessage(.system, """
                        Analyze the text and output exactly 2 lines:
                        Line 1: A single category (one of: Work, Personal, Study, Creative, Meeting, Technical, Other)
                        Line 2: 3-5 relevant tags separated by commas
                        """),
                    LLMMessage(.user, String(text.prefix(2000))),
                ],
                parameters: LLMParameters(maxTokens: 100, temperature: 0.2)
            )
            let lines = response.components(separatedBy: "\n").filter { !$0.isEmpty }
            let category = lines.first?.trimmingCharacters(in: .whitespaces)
            let tags = (lines.count > 1)
                ? lines[1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                : []
            return (category, tags)
        } catch {
            return (nil, [])
        }
    }
}
