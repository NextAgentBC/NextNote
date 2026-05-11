import Foundation

/// Web-search client that talks to a credbroker-mounted Tavily service.
/// Used by the AI chat's `/search` slash command — broker handles auth via
/// Tailscale identity, so no API key is needed on this host.
enum TavilyClient {

    struct SearchResult: Decodable {
        let url: String
        let title: String
        let content: String
    }

    private struct SearchResponse: Decodable {
        let results: [SearchResult]
    }

    enum TavilyError: LocalizedError {
        case noBrokerEndpoint
        case http(Int)
        case decoding

        var errorDescription: String? {
            switch self {
            case .noBrokerEndpoint:
                return "Web search requires the credbroker provider (Local). Switch providers in AI settings or paste search results manually."
            case .http(let code):
                return "Tavily request failed (HTTP \(code))."
            case .decoding:
                return "Tavily response was not valid JSON."
            }
        }
    }

    /// Pull the credbroker root (e.g. `http://100.79.97.110:8800`) out of a
    /// chat base URL like `http://.../v1/proxy/local-llm`. Returns nil when
    /// the active provider doesn't sit behind credbroker — caller surfaces
    /// `.noBrokerEndpoint` so the user knows what to do.
    static func brokerRoot(from chatBaseURL: URL) -> URL? {
        let s = chatBaseURL.absoluteString
        guard let r = s.range(of: "/v1/proxy/") else { return nil }
        return URL(string: String(s[s.startIndex..<r.lowerBound]))
    }

    static func search(query: String, maxResults: Int = 5, broker: URL) async throws -> [SearchResult] {
        let url = broker.appendingPathComponent("v1/proxy/tavily/search")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        let body: [String: Any] = [
            "query": query,
            "max_results": maxResults,
            "search_depth": "basic"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw TavilyError.http(0) }
        guard http.statusCode == 200 else { throw TavilyError.http(http.statusCode) }
        do {
            return try JSONDecoder().decode(SearchResponse.self, from: data).results
        } catch {
            throw TavilyError.decoding
        }
    }

    /// Markdown rendering used both as a chat-block body (so the user sees
    /// what was retrieved) and as the system-message context fed to the LLM
    /// for the follow-up turn. Includes the upstream URL so the user can
    /// verify where the results actually came from.
    static func formatAsMarkdown(query: String, results: [SearchResult], endpoint: URL) -> String {
        var lines: [String] = [
            "🔎 Web search — **\(query)**",
            "Source: Tavily via `\(endpoint.absoluteString)`",
            ""
        ]
        guard !results.isEmpty else {
            lines.append("_No results._")
            return lines.joined(separator: "\n")
        }
        for (i, r) in results.enumerated() {
            let snippet = r.content
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(400)
            lines.append("**[\(i + 1)] \(r.title)**")
            lines.append(r.url)
            lines.append(String(snippet))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Public so the chat view can show the exact upstream URL it's about
    /// to hit before the request goes out.
    static func endpointURL(broker: URL) -> URL {
        broker.appendingPathComponent("v1/proxy/tavily/search")
    }
}
