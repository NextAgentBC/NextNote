import Foundation

// Google AI Studio (Gemini) provider. REST, no SDK dependency.
//
// Endpoint:
//   POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key=API_KEY
//   Body: {"contents":[{"role":"user","parts":[{"text":"..."}]}],
//          "systemInstruction":{"parts":[{"text":"..."}]},
//          "generationConfig":{"maxOutputTokens":N,"temperature":T}}
//
// Free-tier friendly. Model IDs are treated as opaque strings so we don't
// hard-code whatever Google renames them to this week.
@MainActor
final class GeminiProvider: LLMProvider {
    private(set) var lastTokensPerSecond: Double = 0

    /// One or more API keys. When more than one is provided we round-robin
    /// through them and promote the next key on quota errors (HTTP 429)
    /// so a single exhausted key doesn't take the whole app down.
    private let apiKeys: [String]
    private let model: String
    private var keyIndex: Int = 0

    /// Dedicated session with longer timeouts for thinking-class models.
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 300
        cfg.timeoutIntervalForResource = 900
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    init(apiKeys: [String], model: String = "gemini-flash-latest") {
        self.apiKeys = apiKeys.filter { !$0.isEmpty }
        self.model = model
    }

    /// Single-key convenience init.
    convenience init(apiKey: String, model: String = "gemini-flash-latest") {
        self.init(apiKeys: [apiKey], model: model)
    }

    func generate(messages: [LLMMessage], parameters: LLMParameters) async throws -> String {
        guard !apiKeys.isEmpty else {
            throw GeminiError.noKey
        }

        let payload = Self.buildPayload(messages: messages, parameters: parameters)
        let body = try JSONSerialization.data(withJSONObject: payload)

        // Try each key at most once per call. Stop on first success or on
        // a non-quota error (malformed request, etc).
        var lastError: Error = GeminiError.invalidResponse
        for attempt in 0..<apiKeys.count {
            let idx = (keyIndex + attempt) % apiKeys.count
            let key = apiKeys[idx]
            do {
                let text = try await sendOnce(key: key, body: body)
                keyIndex = idx // stick with the working key for the next call
                return text
            } catch GeminiError.http(let code, let snippet) where code == 429 || code == 403 {
                // quota / throttled / key disabled → rotate
                lastError = GeminiError.http(code, snippet)
                continue
            } catch {
                throw error
            }
        }

        // All keys exhausted
        keyIndex = (keyIndex + 1) % apiKeys.count
        throw lastError
    }

    private func sendOnce(key: String, body: Data) async throws -> String {
        let url = Self.endpoint(model: model, apiKey: key)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let start = Date()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.http(http.statusCode, snippet)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = root["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            throw GeminiError.malformed
        }

        let text = parts
            .compactMap { $0["text"] as? String }
            .joined()

        let elapsed = Date().timeIntervalSince(start)
        if elapsed > 0 {
            let approxTokens = Double(text.count) / 4.0
            lastTokensPerSecond = approxTokens / elapsed
        }
        return text
    }

    func generateStream(messages: [LLMMessage], parameters: LLMParameters) -> AsyncThrowingStream<String, Error> {
        // SSE via `:streamGenerateContent?alt=sse` — non-essential for dashboard
        // rollups, which are short enough that non-streaming is fine. If we
        // later need typewriter UI for continueWriting, swap the endpoint
        // and parse `data:` frames. For now: one-shot wrapping of generate().
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else { continuation.finish(); return }
                do {
                    let text = try await self.generate(messages: messages, parameters: parameters)
                    continuation.yield(text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func testConnection() async throws {
        // Gemini 3-class "thinking" models can consume the token budget on
        // internal reasoning and return zero visible text parts when the
        // budget is tight. Give the ping plenty of headroom so we verify
        // auth+routing, not thinking-vs-output accounting.
        _ = try await generate(
            messages: [LLMMessage(.user, "Reply with the single word: ok")],
            parameters: LLMParameters(maxTokens: 256, temperature: 0)
        )
    }

    // MARK: - Helpers

    private static func endpoint(model: String, apiKey: String) -> URL {
        // Key stays in query string — that's Google's documented shape.
        // We never log the full URL.
        var comps = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        return comps.url!
    }

    private static func buildPayload(messages: [LLMMessage], parameters: LLMParameters) -> [String: Any] {
        var systemParts: [[String: Any]] = []
        var contents: [[String: Any]] = []
        for m in messages {
            switch m.role {
            case .system:
                systemParts.append(["text": m.content])
            case .user:
                contents.append([
                    "role": "user",
                    "parts": [["text": m.content]]
                ])
            case .assistant:
                contents.append([
                    "role": "model",
                    "parts": [["text": m.content]]
                ])
            }
        }
        // Disable "thinking" so the whole token budget goes to visible text.
        // Gemini 3-class models otherwise eat most of the budget on internal
        // reasoning and truncate the actual output. For dashboard rollups we
        // want concise rendered Markdown, not chain-of-thought.
        var generationConfig: [String: Any] = [
            "maxOutputTokens": parameters.maxTokens,
            "temperature": parameters.temperature,
            "thinkingConfig": ["thinkingBudget": 0]
        ]

        var payload: [String: Any] = [
            "contents": contents,
            "generationConfig": generationConfig
        ]
        if !systemParts.isEmpty {
            payload["systemInstruction"] = ["parts": systemParts]
        }
        return payload
    }
}

enum GeminiError: LocalizedError {
    case invalidResponse
    case http(Int, String)
    case malformed
    case noKey

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Gemini returned an invalid response."
        case .http(let code, let body):
            // Trim to avoid dumping giant error bodies into UI.
            let snippet = body.prefix(200)
            return "Gemini HTTP \(code): \(snippet)"
        case .malformed: return "Gemini response did not contain expected content.parts[].text."
        case .noKey: return "No Gemini API key configured."
        }
    }
}
