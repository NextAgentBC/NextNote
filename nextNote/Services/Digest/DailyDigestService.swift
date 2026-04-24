import Foundation

// On-first-launch-of-the-day digest. Writes `{vault}/_daily.md` with a
// summary of what changed since the last run plus the current root
// dashboard. Skips itself if quota is nearly empty (<5% RPD left).
//
// No cron, no NSBackgroundActivityScheduler. If the app isn't opened
// that day, the digest simply doesn't run — acceptable trade-off.
@MainActor
final class DailyDigestService {
    static let shared = DailyDigestService()
    private init() {}

    private let lastRunKey = "lastDigestRunAt"
    private let minHoursBetweenRuns: Double = 20

    func generateIfDue() async {
        guard VaultStoreAccess.rootURL != nil else { return }
        let now = Date()
        let last = UserDefaults.standard.double(forKey: lastRunKey)
        if last > 0 {
            let hoursSince = (now.timeIntervalSince1970 - last) / 3600.0
            if hoursSince < minHoursBetweenRuns { return }
        }

        let quota = QuotaTracker.shared
        if quota.remainingPercent < 0.05 {
            // Quota almost exhausted — skip with a published error so the
            // UI can surface it. No network call burned.
            AITextService.shared.bindVault(rootURL: VaultStoreAccess.rootURL!) // keep cache bound
            DashboardService.shared.lastError = "Daily digest skipped: quota <5% remaining."
            return
        }

        do {
            try await run()
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastRunKey)
        } catch {
            DashboardService.shared.lastError = "Daily digest failed: \(error.localizedDescription)"
        }
    }

    func runNow() async {
        do { try await run() } catch {
            DashboardService.shared.lastError = "Daily digest failed: \(error.localizedDescription)"
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastRunKey)
    }

    private func run() async throws {
        guard let vaultRoot = VaultStoreAccess.rootURL else {
            throw DigestError.noVault
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let changes = try ChangeScanner.collect(since: cutoff)

        // Root dashboard body (AI preferred, else pinned).
        let rootDashURL = vaultRoot.appending(path: "_dashboard.md", directoryHint: .notDirectory)
        let rootDashRaw = (try? NoteIO.read(url: rootDashURL)) ?? ""
        let parsed = DashboardDocument.parse(rootDashRaw)
        let rootBody = parsed.ai.isEmpty ? parsed.pinned : parsed.ai

        let prompt = DashboardPrompts.digestUserPrompt(
            rootDashboard: rootBody,
            changes: changes
        )
        let provider = AITextService.shared.currentProvider
        let out = try await provider.generate(
            messages: [
                LLMMessage(.system, DashboardPrompts.system),
                LLMMessage(.user, prompt)
            ],
            parameters: LLMParameters(maxTokens: 1500, temperature: 0.3)
        )

        let header = "# Daily Digest — \(Self.dateFormatter.string(from: Date()))\n\n"
        let body = header + out + "\n"
        let daily = vaultRoot.appending(path: "_daily.md", directoryHint: .notDirectory)
        try NoteIO.write(url: daily, content: body)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()
}

enum DigestError: LocalizedError {
    case noVault
    var errorDescription: String? {
        switch self {
        case .noVault: return "No vault mounted; cannot generate digest."
        }
    }
}

// MARK: - File change scan

@MainActor
enum ChangeScanner {
    /// Returns [(topTopic, [relativePath])] for .md files whose mtime is
    /// after `since`. Top topic = first path component; "" if at root.
    static func collect(since: Date) throws -> [(String, [String])] {
        guard let root = VaultStoreAccess.rootURL else { return [] }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var grouped: [String: [String]] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            if values.isDirectory == true { continue }
            guard url.pathExtension.lowercased() == "md",
                  let mtime = values.contentModificationDate,
                  mtime >= since
            else { continue }

            let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
            let topic = rel.split(separator: "/").first.map(String.init) ?? ""
            let topKey = (topic.hasSuffix(".md")) ? "" : topic
            grouped[topKey, default: []].append(rel)
        }
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value.sorted()) }
    }
}
