import Foundation

// Token-bucket limiter. `acquire()` suspends until a token is free.
// Refill runs lazily on each acquire — no background timer, no leaks.
//
// Default config (10 RPM) fits Gemini free tier headroom.
actor RateLimiter {
    private let capacity: Double
    private let refillPerSecond: Double
    private var tokens: Double
    private var lastRefill: Date

    init(capacity: Double = 10, refillPerSecond: Double = 10.0 / 60.0) {
        self.capacity = capacity
        self.refillPerSecond = refillPerSecond
        self.tokens = capacity
        self.lastRefill = Date()
    }

    func acquire() async {
        while true {
            refill()
            if tokens >= 1 {
                tokens -= 1
                return
            }
            let deficit = 1 - tokens
            let waitSeconds = max(0.05, deficit / refillPerSecond)
            try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
        }
    }

    private func refill() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        tokens = min(capacity, tokens + elapsed * refillPerSecond)
        lastRefill = now
    }
}
