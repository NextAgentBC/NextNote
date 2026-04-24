import Foundation

// MARK: - Model State

enum ModelState: Equatable, Sendable {
    case notDownloaded
    case downloading(progress: Double)
    case ready
    case loading
    case error(String)
}

// MARK: - Provider Selection

enum AIProviderType: String, CaseIterable, Sendable {
    case onDevice = "on_device"
    case remote = "remote"
    case gemini = "gemini"

    var displayName: String {
        switch self {
        case .onDevice: return "On-Device (MLX)"
        case .remote: return "Remote (OpenAI-compatible)"
        case .gemini: return "Google Gemini (Free tier)"
        }
    }
}

// MARK: - Errors

enum AIError: LocalizedError, Sendable {
    case modelNotLoaded
    case generationFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "AI model is not loaded. Please download it in Settings."
        case .generationFailed(let msg):
            return "Generation failed: \(msg)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        }
    }
}

// MARK: - AI Feature Types

enum SummaryLength: Sendable {
    case brief, medium, detailed

    var instruction: String {
        switch self {
        case .brief:    return "1-2 sentences"
        case .medium:   return "3-5 sentences"
        case .detailed: return "a short paragraph"
        }
    }
}

enum PolishStyle: String, CaseIterable, Sendable {
    case formal  = "Formal"
    case concise = "Concise"
    case vivid   = "Vivid"
}

struct GrammarSuggestion: Identifiable, Sendable {
    let id = UUID()
    let range: Range<String.Index>
    let original: String
    let suggestion: String
    let explanation: String
}

// MARK: - Model Catalog

struct ModelOption: Identifiable, Sendable {
    let id: String          // HuggingFace model ID
    let name: String
    let description: String
    let size: String
    let requiresToken: Bool
    let isMultimodal: Bool
}
