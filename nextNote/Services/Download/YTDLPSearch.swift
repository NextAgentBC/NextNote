import Foundation

// Thin yt-dlp `ytsearch:` wrapper. `--flat-playlist` keeps each result to one
// metadata round-trip instead of fully resolving its manifest — a 5-result
// search returns in ~1–2s on a decent connection, compared to ~15s if we let
// yt-dlp probe every candidate.
@MainActor
enum YTDLPSearch {

    struct Result: Identifiable, Sendable, Hashable {
        var id: String            // YouTube video id
        var title: String
        var uploader: String?
        var duration: String?     // "3:42" or nil

        var watchURL: URL {
            URL(string: "https://www.youtube.com/watch?v=\(id)")!
        }
    }

    enum SearchError: LocalizedError {
        case launchFailed(String)
        case nonZeroExit(Int32, String)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let m): return "yt-dlp search failed to launch: \(m)"
            case .nonZeroExit(let code, let tail):
                return "yt-dlp search exited \(code): \(tail.suffix(200))"
            }
        }
    }

    /// Run `ytsearch<count>:<query>` and return parsed results. `count` is
    /// clamped to [1, 20] — beyond that YouTube's search API gets noisy and
    /// the UI can't reasonably present it anyway.
    static func search(
        query: String,
        count: Int = 8,
        binary: URL
    ) async throws -> [Result] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let n = max(1, min(count, 20))

        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "--skip-download",
            "--flat-playlist",
            "--no-warnings",
            "--print", "%(id)s\t%(title)s\t%(uploader)s\t%(duration_string)s",
            "ytsearch\(n):\(trimmed)",
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw SearchError.launchFailed(error.localizedDescription)
        }

        // Small output (one line per result), pipes won't fill — wait then drain.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }

        let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()

        guard process.terminationStatus == 0 else {
            let tail = String(data: errData, encoding: .utf8) ?? ""
            throw SearchError.nonZeroExit(process.terminationStatus, tail)
        }

        let text = String(data: outData, encoding: .utf8) ?? ""
        var results: [Result] = []
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { continue }
            let id = parts[0].trimmingCharacters(in: .whitespaces)
            let title = parts[1].trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty, !title.isEmpty else { continue }

            func pick(_ i: Int) -> String? {
                guard i < parts.count else { return nil }
                let v = parts[i].trimmingCharacters(in: .whitespaces)
                return (v.isEmpty || v == "NA" || v == "None") ? nil : v
            }

            results.append(Result(
                id: id,
                title: title,
                uploader: pick(2),
                duration: pick(3)
            ))
        }
        return results
    }

    /// Heuristic: is this text a URL (paste it, download it) vs a search query
    /// (run ytsearch). Accepts http/https + scheme-less youtube.com / youtu.be.
    static func isLikelyURL(_ text: String) -> Bool {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return true }
        if s.hasPrefix("youtube.com/") || s.hasPrefix("www.youtube.com/") { return true }
        if s.hasPrefix("youtu.be/") { return true }
        if s.hasPrefix("m.youtube.com/") { return true }
        return false
    }
}
