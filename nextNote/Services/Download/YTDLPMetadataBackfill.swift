import Foundation

// Re-fetches yt-dlp metadata for tracks whose filenames still carry the old
// `--restrict-filenames` underscore-pinyin mangling. Walks the library, finds
// entries ending with an 11-char YouTube video ID, queries yt-dlp with
// --skip-download to get the real title + uploader, renames the file on disk,
// and re-brands the Track so the queue shows "邓紫棋 — 光年之外" instead of
// "G.E.M._LIGHT_YEAR-T4SimnaiktU".
//
// Network-bound: each track is one yt-dlp call. Runs serially to avoid
// hammering YouTube (and to keep progress output readable).
@MainActor
enum YTDLPMetadataBackfill {

    struct Outcome: Sendable {
        let scanned: Int
        let updated: Int
        let skipped: Int
        let failed: Int
    }

    enum Status: Sendable {
        case progress(idx: Int, total: Int, message: String)
        case done(Outcome)
    }

    /// Run the backfill. `onStatus` fires on the main actor for UI binding.
    static func run(
        library: MediaLibrary,
        binary: URL,
        onStatus: @MainActor @escaping (Status) -> Void
    ) async {
        // Snapshot candidates whose filename matches either filename scheme:
        //   old: "<title>-<11charID>.ext"                (restrict-filenames)
        //   new: "<uploader> - <title> [<11charID>].ext" (current)
        // We only rewrite the old ones — new downloads already look fine.
        let candidates: [(id: UUID, url: URL, videoID: String)] = library.tracks.compactMap { t in
            guard let vid = extractVideoID(from: t.url) else { return nil }
            // Skip already-clean files (bracketed id = new template → no work).
            if t.url.deletingPathExtension().lastPathComponent.contains("[\(vid)]") {
                return nil
            }
            return (t.id, t.url, vid)
        }

        let total = candidates.count
        var updated = 0
        var failed = 0
        var skipped = 0

        for (i, entry) in candidates.enumerated() {
            onStatus(.progress(
                idx: i + 1, total: total,
                message: "Fetching metadata for \(entry.videoID)…"
            ))

            do {
                let meta = try await fetch(videoID: entry.videoID, binary: binary)
                let title = (meta.title?.nonEmpty) ?? entry.url.deletingPathExtension().lastPathComponent
                let uploader = meta.uploader?.nonEmpty ?? meta.channel?.nonEmpty
                let ext = entry.url.pathExtension
                let sanitizedUploader = uploader.map { sanitizeForFilename($0) } ?? "Unknown"
                let sanitizedTitle = sanitizeForFilename(title)
                let newBaseName = "\(sanitizedUploader) - \(sanitizedTitle) [\(entry.videoID)]"
                let newFileName = ext.isEmpty ? newBaseName : "\(newBaseName).\(ext)"
                let destDir = entry.url.deletingLastPathComponent()
                let newURL = destDir.appendingPathComponent(newFileName)

                if newURL.path == entry.url.path {
                    skipped += 1
                    continue
                }

                if FileManager.default.fileExists(atPath: newURL.path) {
                    // Don't stomp a pre-existing file of the same name.
                    skipped += 1
                    continue
                }

                try FileManager.default.moveItem(at: entry.url, to: newURL)

                let displayArtist = uploader
                let displayTitle = displayArtist.map { "\($0) — \(title)" } ?? title
                library.updateTrackURL(id: entry.id, newURL: newURL, newTitle: displayTitle)

                updated += 1
                onStatus(.progress(
                    idx: i + 1, total: total,
                    message: "✓ \(displayTitle)"
                ))
            } catch {
                failed += 1
                onStatus(.progress(
                    idx: i + 1, total: total,
                    message: "✗ \(entry.videoID): \(error.localizedDescription)"
                ))
            }
        }

        onStatus(.done(Outcome(
            scanned: total, updated: updated, skipped: skipped, failed: failed
        )))
    }

    // MARK: - Video ID extraction

    /// Pull an 11-char YouTube video ID out of a filename. Tries the new
    /// bracketed suffix first (" [xxxxxxxxxxx].ext"), then the legacy dash
    /// suffix ("-xxxxxxxxxxx.ext"). Returns nil if neither matches.
    static func extractVideoID(from url: URL) -> String? {
        let stem = url.deletingPathExtension().lastPathComponent

        // New template: "... [ID]"
        if let r = stem.range(of: #"\[([A-Za-z0-9_-]{11})\]\s*$"#, options: .regularExpression) {
            let match = String(stem[r])
            // Strip brackets.
            return match
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }

        // Legacy: "...-ID" at end-of-stem. Guard against false positives by
        // requiring a dash immediately before the 11-char chunk and requiring
        // the chunk to contain at least one uppercase AND one digit/dash —
        // typical YT id entropy. (Pure lowercase-only 11-char words exist as
        // English filenames; skip those to avoid misfiring.)
        let pattern = #"-([A-Za-z0-9_-]{11})$"#
        if let r = stem.range(of: pattern, options: .regularExpression) {
            let id = String(stem[r]).dropFirst()  // drop leading "-"
            let hasUpper = id.contains(where: { $0.isUppercase })
            let hasDigitOrDash = id.contains(where: { $0.isNumber || $0 == "_" || $0 == "-" })
            if hasUpper && hasDigitOrDash {
                return String(id)
            }
        }

        return nil
    }

    // MARK: - yt-dlp call

    struct FetchedMetadata: Sendable {
        var title: String?
        var uploader: String?
        var channel: String?
    }

    private static func fetch(videoID: String, binary: URL) async throws -> FetchedMetadata {
        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "--skip-download",
            "--no-warnings",
            "--no-playlist",
            "--print", "%(title)s\t%(uploader)s\t%(channel)s",
            "https://www.youtube.com/watch?v=\(videoID)",
        ]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Wait for termination BEFORE draining pipes — yt-dlp --skip-download
        // emits a single print line, so pipe buffers never fill.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }

        let outData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        let errData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()

        guard process.terminationStatus == 0 else {
            let tail = String(data: errData, encoding: .utf8) ?? ""
            throw NSError(
                domain: "YTDLPMetadataBackfill", code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "yt-dlp failed: \(tail.suffix(200))"]
            )
        }

        let out = String(data: outData, encoding: .utf8) ?? ""
        let parts = out
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .first?
            .split(separator: "\t", omittingEmptySubsequences: false)
            .map(String.init) ?? []

        func pick(_ i: Int) -> String? {
            guard i < parts.count else { return nil }
            let v = parts[i].trimmingCharacters(in: .whitespaces)
            return (v.isEmpty || v == "NA" || v == "None") ? nil : v
        }

        return FetchedMetadata(title: pick(0), uploader: pick(1), channel: pick(2))
    }

    // MARK: - Filename hygiene

    private static func sanitizeForFilename(_ s: String) -> String {
        let bad: Set<Character> = ["/", ":", "\\", "*", "?", "\"", "<", ">", "|", "\0"]
        var out = s.filter { !bad.contains($0) }
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        while out.hasPrefix(".") { out.removeFirst() }
        if out.count > 100 { out = String(out.prefix(100)) }
        return out.isEmpty ? "Untitled" : out
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
