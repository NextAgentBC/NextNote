import Foundation

// Decorator. Wraps any LLMProvider with:
//   - content-hash cache lookup (skip identical calls)
//   - token-bucket rate limit (respect free-tier RPM)
//   - quota tracker increment (surface remaining RPD in the UI)
//
// Keeps provider implementations clean — none of them need to know about
// throttling or caching.
@MainActor
final class ThrottledCachedProvider: LLMProvider {
    var lastTokensPerSecond: Double { inner.lastTokensPerSecond }

    private let inner: any LLMProvider
    private let limiter: RateLimiter
    private let cache: SummaryCache?
    private let modelId: String
    private let promptVersion: String

    init(
        inner: any LLMProvider,
        limiter: RateLimiter,
        cache: SummaryCache?,
        modelId: String,
        promptVersion: String = "v1"
    ) {
        self.inner = inner
        self.limiter = limiter
        self.cache = cache
        self.modelId = modelId
        self.promptVersion = promptVersion
    }

    func generate(messages: [LLMMessage], parameters: LLMParameters) async throws -> String {
        let key = SummaryCache.makeKey(
            model: modelId,
            temperature: parameters.temperature,
            promptVersion: promptVersion,
            inputs: messages.map { "\($0.role):\($0.content)" }
        )

        if let cache, let hit = await cache.get(key) {
            return hit
        }

        await limiter.acquire()
        let out = try await inner.generate(messages: messages, parameters: parameters)
        QuotaTracker.shared.increment()

        if let cache {
            await cache.put(key, value: out)
            await cache.flush()
        }
        return out
    }

    func generateStream(messages: [LLMMessage], parameters: LLMParameters) -> AsyncThrowingStream<String, Error> {
        // Streaming bypasses cache (we want live output). Still rate-limited.
        AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else { continuation.finish(); return }
                do {
                    await self.limiter.acquire()
                    QuotaTracker.shared.increment()
                    let stream = self.inner.generateStream(messages: messages, parameters: parameters)
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func testConnection() async throws {
        try await inner.testConnection()
    }
}
