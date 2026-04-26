import Foundation

struct AIProvider: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var kind: Kind
    var chatBaseURL: URL
    var chatModel: String
    var embedBaseURL: URL
    var embedModel: String
    var vectorDSN: String?
    var requiresAPIKey: Bool

    enum Kind: String, Codable {
        case openaiCompat, anthropic
    }

    static let presets: [AIProvider] = [localTailnet, openAI, anthropic, ollamaLocalhost, custom]

    static let localTailnet = AIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Local (Tailnet Qwen3.6)",
        kind: .openaiCompat,
        chatBaseURL: URL(string: "http://100.113.17.31:9999")!,
        chatModel: "Qwen3.6-35B-A3B-MXFP4_MOE.gguf",
        embedBaseURL: URL(string: "http://100.79.97.110:8081")!,
        embedModel: "qwen3-embed-8b",
        vectorDSN: "postgresql://hermes:hermes_memory_2026@100.79.97.110:5433/hermes_memory",
        requiresAPIKey: false
    )

    static let openAI = AIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "OpenAI",
        kind: .openaiCompat,
        chatBaseURL: URL(string: "https://api.openai.com")!,
        chatModel: "gpt-4o",
        embedBaseURL: URL(string: "https://api.openai.com")!,
        embedModel: "text-embedding-3-small",
        vectorDSN: nil,
        requiresAPIKey: true
    )

    static let anthropic = AIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Anthropic",
        kind: .anthropic,
        chatBaseURL: URL(string: "https://api.anthropic.com")!,
        chatModel: "claude-opus-4-5",
        embedBaseURL: URL(string: "https://api.anthropic.com")!,
        embedModel: "",
        vectorDSN: nil,
        requiresAPIKey: true
    )

    static let ollamaLocalhost = AIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Ollama (localhost)",
        kind: .openaiCompat,
        chatBaseURL: URL(string: "http://localhost:11434")!,
        chatModel: "llama3.2",
        embedBaseURL: URL(string: "http://localhost:11434")!,
        embedModel: "nomic-embed-text",
        vectorDSN: nil,
        requiresAPIKey: false
    )

    static let custom = AIProvider(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        name: "Custom",
        kind: .openaiCompat,
        chatBaseURL: URL(string: "http://localhost:8080")!,
        chatModel: "",
        embedBaseURL: URL(string: "http://localhost:8080")!,
        embedModel: "",
        vectorDSN: nil,
        requiresAPIKey: false
    )
}
