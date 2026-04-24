import Foundation

/// LLM provider that calls any OpenAI-compatible endpoint (llama.cpp server,
/// Ollama, vLLM, LM Studio, or any self-hosted gateway). All methods run on
/// the main actor; URLSession awaits are non-blocking suspensions.
@MainActor
final class RemoteOpenAIProvider: LLMProvider {

    let baseURL: String
    let model: String
    let apiKey: String?

    /// Attached to every request body. Used to pass Qwen-specific
    /// `chat_template_kwargs.enable_thinking = false` so the model skips the
    /// reasoning stage when we just want a fast answer.
    let extraBody: [String: Any]

    private(set) var lastTokensPerSecond: Double = 0   // remote API doesn't report this

    /// Long-running session for chat completions. URLSession.shared's 60s
    /// request timeout is too short when a thinking model spends >60s before
    /// emitting its first visible token.
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 300    // 5 min waiting for first byte
        cfg.timeoutIntervalForResource = 900   // 15 min total
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    init(baseURL: String, model: String, apiKey: String? = nil, extraBody: [String: Any] = [:]) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.extraBody = extraBody
    }

    // MARK: - LLMProvider

    func generate(messages: [LLMMessage], parameters: LLMParameters) async throws -> String {
        let url = try completionsURL()
        let bodyData = try buildBody(messages: messages, parameters: parameters, stream: false)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, body: data)

        let decoded = try JSONDecoder().decode(CompletionResponse.self, from: data)
        return decoded.choices.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func generateStream(messages: [LLMMessage], parameters: LLMParameters) -> AsyncThrowingStream<String, Error> {
        let urlResult = Result { try completionsURL() }
        let bodyResult = Result { try buildBody(messages: messages, parameters: parameters, stream: true) }
        let apiKey = self.apiKey
        let streamSession = self.session

        return AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    let url = try urlResult.get()
                    let body = try bodyResult.get()

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let apiKey, !apiKey.isEmpty {
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    request.httpBody = body

                    let (bytes, response) = try await streamSession.bytes(for: request)
                    try validateHTTP(response, body: nil)

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(CompletionChunk.self, from: data),
                           let content = chunk.choices.first?.delta.content,
                           !content.isEmpty {
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func testConnection() async throws {
        guard let url = URL(string: baseURL + "/models") else {
            throw AIError.networkError("Invalid base URL: \(baseURL)")
        }
        var request = URLRequest(url: url)
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, body: data)
    }

    // MARK: - Helpers

    private func completionsURL() throws -> URL {
        guard let url = URL(string: baseURL + "/chat/completions") else {
            throw AIError.networkError("Invalid base URL: \(baseURL)")
        }
        return url
    }

    /// Serialize the request body as JSON. We use a dict so extra_body keys
    /// like `chat_template_kwargs` can be passed through without extending
    /// the Codable type every time.
    private func buildBody(
        messages: [LLMMessage],
        parameters: LLMParameters,
        stream: Bool
    ) throws -> Data {
        var payload: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role.apiString, "content": $0.content] },
            "stream": stream,
            "max_tokens": parameters.maxTokens,
            "temperature": Double(parameters.temperature)
        ]
        for (k, v) in extraBody {
            payload[k] = v
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }
}

// MARK: - HTTP validation

private func validateHTTP(_ response: URLResponse, body: Data?) throws {
    guard let http = response as? HTTPURLResponse else { return }
    guard (200..<300).contains(http.statusCode) else {
        let snippet = body.flatMap { String(data: $0, encoding: .utf8)?.prefix(200) }.map(String.init) ?? ""
        throw AIError.networkError("HTTP \(http.statusCode): \(snippet)")
    }
}

// MARK: - LLMMessage role mapping

private extension LLMMessage.Role {
    var apiString: String {
        switch self {
        case .system:    return "system"
        case .user:      return "user"
        case .assistant: return "assistant"
        }
    }
}

// MARK: - Decodable response types

// Non-streaming response
private struct CompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message?
    }

    struct Message: Decodable {
        let content: String?
    }
}

// Streaming chunk
private struct CompletionChunk: Decodable {
    let choices: [ChunkChoice]

    struct ChunkChoice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }
}
