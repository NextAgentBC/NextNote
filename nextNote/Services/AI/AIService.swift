import Foundation
import Combine

enum AIError: LocalizedError {
    case unreachable
    case badResponse(Int)
    case decoding
    case notImplemented
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .unreachable: return "AI endpoint unreachable"
        case .badResponse(let code): return "Unexpected HTTP \(code)"
        case .decoding: return "Failed to decode response"
        case .notImplemented: return "Not implemented for this provider"
        case .missingAPIKey: return "API key required but not configured"
        }
    }
}

@MainActor
final class AIService: ObservableObject {
    private let settings: AIProviderSettings
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var currentProvider: AIProvider

    init(settings: AIProviderSettings = .shared) {
        self.settings = settings
        self.currentProvider = settings.activeProvider

        settings.$activeProvider
            .receive(on: RunLoop.main)
            .assign(to: \.currentProvider, on: self)
            .store(in: &cancellables)
    }

    // MARK: - Chat (SSE streaming)

    func chat(messages: [ChatMessage], stream: Bool = true) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let provider = self.currentProvider
                    guard provider.kind == .openaiCompat else {
                        continuation.finish(throwing: AIError.notImplemented)
                        return
                    }

                    let url = provider.chatBaseURL.appendingPathComponent("v1/chat/completions")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    if provider.requiresAPIKey {
                        let key = self.settings.apiKey(for: provider)
                        guard let key else {
                            continuation.finish(throwing: AIError.missingAPIKey)
                            return
                        }
                        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    }

                    let body = ChatCompletionRequest(
                        model: provider.chatModel,
                        messages: messages.map { ChatCompletionMessage(role: $0.role.rawValue, content: $0.content) },
                        stream: stream
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    if stream {
                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        guard let httpResponse = response as? HTTPURLResponse else {
                            continuation.finish(throwing: AIError.unreachable)
                            return
                        }
                        guard httpResponse.statusCode == 200 else {
                            continuation.finish(throwing: AIError.badResponse(httpResponse.statusCode))
                            return
                        }

                        var buffer = ""
                        for try await byte in bytes {
                            let char = String(bytes: [byte], encoding: .utf8) ?? ""
                            buffer += char

                            while let range = buffer.range(of: "\n\n") {
                                let chunk = String(buffer[buffer.startIndex..<range.lowerBound])
                                buffer = String(buffer[range.upperBound...])

                                for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
                                    let lineStr = String(line)
                                    guard lineStr.hasPrefix("data: ") else { continue }
                                    let payload = String(lineStr.dropFirst(6))
                                    if payload == "[DONE]" {
                                        continuation.finish()
                                        return
                                    }
                                    if let data = payload.data(using: .utf8),
                                       let sseChunk = try? JSONDecoder().decode(SSEChunk.self, from: data),
                                       let content = sseChunk.choices.first?.delta.content {
                                        continuation.yield(content)
                                    }
                                }
                            }
                        }
                        continuation.finish()
                    } else {
                        let (data, response) = try await URLSession.shared.data(for: request)
                        guard let httpResponse = response as? HTTPURLResponse else {
                            continuation.finish(throwing: AIError.unreachable)
                            return
                        }
                        guard httpResponse.statusCode == 200 else {
                            continuation.finish(throwing: AIError.badResponse(httpResponse.statusCode))
                            return
                        }
                        guard let completion = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data),
                              let content = completion.choices.first?.message.content else {
                            continuation.finish(throwing: AIError.decoding)
                            return
                        }
                        continuation.yield(content)
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Complete (non-streaming)

    func complete(prompt: String, system: String? = nil) async throws -> String {
        var messages: [ChatMessage] = []
        if let system {
            messages.append(ChatMessage(role: .system, content: system))
        }
        messages.append(ChatMessage(role: .user, content: prompt))

        var result = ""
        for try await chunk in chat(messages: messages, stream: false) {
            result += chunk
        }
        return result
    }

    // MARK: - Embed

    func embed(_ texts: [String]) async throws -> [[Float]] {
        let provider = currentProvider
        guard provider.kind == .openaiCompat else { throw AIError.notImplemented }

        let url = provider.embedBaseURL.appendingPathComponent("v1/embeddings")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if provider.requiresAPIKey {
            let key = settings.apiKey(for: provider)
            guard let key else { throw AIError.missingAPIKey }
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let body = EmbeddingRequest(model: provider.embedModel, input: texts)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AIError.unreachable }
        guard httpResponse.statusCode == 200 else { throw AIError.badResponse(httpResponse.statusCode) }
        guard let result = try? JSONDecoder().decode(EmbeddingResponse.self, from: data) else {
            throw AIError.decoding
        }
        return result.data.map { $0.embedding }
    }

    // MARK: - Test Connection

    struct TestResult {
        let chat: Bool
        let embed: Bool
        let postgres: Bool
        let chatError: String?
        let embedError: String?
        let postgresError: String?
    }

    func testConnection(vectorStore: VectorStore? = nil) async -> TestResult {
        let provider = currentProvider

        async let chatResult = testChat(provider: provider)
        async let embedResult = testEmbed(provider: provider)

        var postgresOK = false
        var postgresErr: String? = nil
        if let store = vectorStore, provider.vectorDSN != nil {
            do {
                try await store.testConnection()
                postgresOK = true
            } catch {
                postgresErr = error.localizedDescription
            }
        } else if provider.vectorDSN == nil {
            postgresErr = "No DSN configured"
        }

        let (chat, embed) = await (chatResult, embedResult)
        return TestResult(
            chat: chat.0,
            embed: embed.0,
            postgres: postgresOK,
            chatError: chat.1,
            embedError: embed.1,
            postgresError: postgresErr
        )
    }

    private func testChat(provider: AIProvider) async -> (Bool, String?) {
        let url = provider.chatBaseURL.appendingPathComponent("v1/models")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        if provider.requiresAPIKey {
            let key = settings.apiKey(for: provider)
            if let key {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return (false, "No HTTP response") }
            return http.statusCode == 200 ? (true, nil) : (false, "HTTP \(http.statusCode)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func testEmbed(provider: AIProvider) async -> (Bool, String?) {
        let url = provider.embedBaseURL.appendingPathComponent("v1/embeddings")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5

        if provider.requiresAPIKey {
            let key = settings.apiKey(for: provider)
            if let key {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        }

        let body = EmbeddingRequest(model: provider.embedModel, input: ["ping"])
        guard let encoded = try? JSONEncoder().encode(body) else { return (false, "Encode error") }
        request.httpBody = encoded

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return (false, "No HTTP response") }
            return http.statusCode == 200 ? (true, nil) : (false, "HTTP \(http.statusCode)")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// MARK: - Request / Response Types

private struct ChatCompletionMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatCompletionMessage]
    let stream: Bool
}

private struct SSEChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta
    }
    let choices: [Choice]
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct EmbeddingRequest: Codable {
    let model: String
    let input: [String]
}

private struct EmbeddingResponse: Decodable {
    struct EmbeddingItem: Decodable {
        let embedding: [Float]
    }
    let data: [EmbeddingItem]
}
