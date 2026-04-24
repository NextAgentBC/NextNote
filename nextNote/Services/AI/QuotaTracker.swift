import Foundation
import SwiftUI

// Tracks requests-per-day for the remote AI tier so we can show usage in
// the status bar and skip expensive jobs (daily digest) when quota is
// nearly exhausted. Persists in UserDefaults, resets at local-midnight.
@MainActor
final class QuotaTracker: ObservableObject {
    static let shared = QuotaTracker()

    @Published private(set) var requestsToday: Int = 0
    @Published var dailyLimit: Int = 250 // conservative Gemini flash default

    private let defaults = UserDefaults.standard
    private let countKey = "quotaRequestsToday"
    private let dayKey = "quotaDayEpoch"

    private init() {
        reloadIfNewDay()
    }

    func increment() {
        reloadIfNewDay()
        requestsToday += 1
        defaults.set(requestsToday, forKey: countKey)
    }

    var remaining: Int {
        max(0, dailyLimit - requestsToday)
    }

    var remainingPercent: Double {
        guard dailyLimit > 0 else { return 0 }
        return Double(remaining) / Double(dailyLimit)
    }

    private func reloadIfNewDay() {
        let today = Self.startOfDay(Date()).timeIntervalSince1970
        let stored = defaults.double(forKey: dayKey)
        if stored != today {
            requestsToday = 0
            defaults.set(today, forKey: dayKey)
            defaults.set(0, forKey: countKey)
        } else {
            requestsToday = defaults.integer(forKey: countKey)
        }
    }

    private static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}
