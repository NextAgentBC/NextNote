import Foundation

// MARK: - Message

struct LLMMessage: Sendable {
    enum Role: Sendable {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String

    init(_ role: Role, _ content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - Parameters

struct LLMParameters: Sendable {
    var maxTokens: Int
    var temperature: Float

    init(maxTokens: Int = 2048, temperature: Float = 0.3) {
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

// MARK: - Protocol

/// Abstraction over on-device MLX inference and remote OpenAI-compatible endpoints.
/// Marked @MainActor so Swift 6 treats all conformances as main-actor-isolated,
/// avoiding cross-actor conformance errors with the concrete @MainActor classes.
@MainActor
protocol LLMProvider: AnyObject {
    /// Tokens generated per second during the most recent call. 0 if unavailable.
    var lastTokensPerSecond: Double { get }

    /// Run a blocking (non-streaming) completion and return the full text.
    func generate(messages: [LLMMessage], parameters: LLMParameters) async throws -> String

    /// Return a stream that yields text tokens as they are produced.
    func generateStream(messages: [LLMMessage], parameters: LLMParameters) -> AsyncThrowingStream<String, Error>

    /// Verify the provider is reachable / ready. Throws on failure.
    func testConnection() async throws
}
