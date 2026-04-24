import Foundation
import MLX
import MLXLLM
import MLXVLM
import MLXLMCommon
import MLXLMTokenizers
import MLXLMHFAPI

/// Manages the MLX on-device model lifecycle: download, load, unload, delete.
/// All UI state is published on the main actor.
@MainActor
final class AIModelManager: ObservableObject {

    static let shared = AIModelManager()

    // MARK: - Published state

    @Published var modelState: ModelState = .notDownloaded

    // MARK: - Internal

    /// Live model container — used by MLXProvider for inference.
    private(set) var container: MLXLMCommon.ModelContainer?

    private var modelId: String {
        UserPreferences.shared.aiModelId
    }

    private init() {}

    // MARK: - Model catalog

    static let availableModels: [ModelOption] = [
        // — Recommended —
        ModelOption(
            id: "mlx-community/Qwen3-4B-4bit",
            name: "Qwen 3 4B ⭐",
            description: "推荐 · 思考模式，中英双语最强",
            size: "~2.5 GB",
            requiresToken: false,
            isMultimodal: false
        ),
        // — Multimodal (VLM) —
        ModelOption(
            id: "lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit",
            name: "Qwen 3 VL 4B 📷",
            description: "多模态 · 看图+文本，中文最强",
            size: "~3 GB",
            requiresToken: false,
            isMultimodal: true
        ),
        ModelOption(
            id: "mlx-community/gemma-3-4b-it-qat-4bit",
            name: "Gemma 3 4B 📷",
            description: "多模态 · Google 96万次下载",
            size: "~2.5 GB",
            requiresToken: false,
            isMultimodal: true
        ),
        // — Lightweight —
        ModelOption(
            id: "mlx-community/Qwen3-1.7B-4bit",
            name: "Qwen 3 1.7B",
            description: "轻量思考模式，手机首选",
            size: "~1.2 GB",
            requiresToken: false,
            isMultimodal: false
        ),
        ModelOption(
            id: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            name: "Qwen 2.5 1.5B",
            description: "已验证可用，中文优秀",
            size: "~1.0 GB",
            requiresToken: false,
            isMultimodal: false
        ),
        // — Mac large —
        ModelOption(
            id: "mlx-community/Qwen3-8B-4bit",
            name: "Qwen 3 8B",
            description: "最聪明，Mac 推荐（需 6GB+）",
            size: "~5 GB",
            requiresToken: false,
            isMultimodal: false
        ),
    ]

    // MARK: - Hub helper

    private func makeHubClient() -> HubClient {
        let token = UserPreferences.shared.hfToken
        guard !token.isEmpty else { return HubClient.default }
        return HubClient(host: HubClient.defaultHost, bearerToken: token)
    }

    // MARK: - Download

    /// Download model from HuggingFace. Tries LLM factory first, then VLM.
    func downloadModel() async {
        modelState = .downloading(progress: 0)

        let modelConfig = ModelConfiguration(id: modelId)
        let hub = makeHubClient()
        let tokenizer = TokenizersLoader()
        let progressHandler: @Sendable (Progress) -> Void = { progress in
            Task { @MainActor [weak self] in
                self?.modelState = .downloading(progress: progress.fractionCompleted)
            }
        }

        do {
            let c = try await LLMModelFactory.shared.loadContainer(
                from: hub, using: tokenizer, configuration: modelConfig,
                progressHandler: progressHandler
            )
            self.container = c
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
            modelState = .ready
        } catch {
            let llmError = error.localizedDescription
            do {
                let c = try await VLMModelFactory.shared.loadContainer(
                    from: hub, using: tokenizer, configuration: modelConfig,
                    progressHandler: progressHandler
                )
                self.container = c
                MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
                modelState = .ready
            } catch {
                modelState = .error("LLM: \(llmError)\nVLM: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Load (from cache)

    func loadModel() async {
        guard container == nil else { modelState = .ready; return }

        modelState = .loading
        let modelConfig = ModelConfiguration(id: modelId)
        let hub = makeHubClient()
        let tokenizer = TokenizersLoader()

        do {
            let c = try await LLMModelFactory.shared.loadContainer(
                from: hub, using: tokenizer, configuration: modelConfig
            )
            self.container = c
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
            modelState = .ready
        } catch {
            do {
                let c = try await VLMModelFactory.shared.loadContainer(
                    from: hub, using: tokenizer, configuration: modelConfig
                )
                self.container = c
                MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
                modelState = .ready
            } catch {
                modelState = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Unload / Delete

    func unloadModel() {
        container = nil
        modelState = .notDownloaded
    }

    func deleteModel() {
        container = nil

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        if let hfCache = cacheDir?.appendingPathComponent("huggingface") {
            let folderName = "models--" + modelId.replacingOccurrences(of: "/", with: "--")
            let modelDir = hfCache
                .appendingPathComponent("hub")
                .appendingPathComponent(folderName)
            try? FileManager.default.removeItem(at: modelDir)
        }

        modelState = .notDownloaded
    }
}
