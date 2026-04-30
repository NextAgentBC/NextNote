import Foundation

// Asks the configured LLM to pull a clean (artist, song) pair out of a messy
// media title, routed into a single-level folder at the chosen root:
//
//     <root>/<Artist>/<Artist> - <Song>[.ext]
//
// No top-level Category/Subcategory tree — all media groups by the performer
// (or show host / creator). The LLM canonicalizes names so "G.E.M." and
// "Gloria Tang" both resolve to the one "邓紫棋" folder that's already
// on disk, avoiding English/Chinese dupes.
@MainActor
enum MediaCategorizer {

    /// Output of `cleanAndClassify`.
    struct Cleaned: Sendable, Equatable {
        var artist: String?           // canonical primary artist (folder name)
        var collaborators: [String]   // additional artists for collabs
        var song: String?             // clean song title, no marketing noise

        /// Combined folder name. Single artist → "Artist". Collab → "A & B".
        var folderName: String? {
            guard let a = artist, !a.isEmpty else { return nil }
            if collaborators.isEmpty { return a }
            return ([a] + collaborators).joined(separator: " & ")
        }
    }

    enum CategorizeError: LocalizedError {
        case emptyResponse
        case invalidJSON(String)
        case moveFailed(String)

        var errorDescription: String? {
            switch self {
            case .emptyResponse: return "AI returned an empty classification."
            case .invalidJSON(let raw):
                return "AI response did not parse as JSON:\n\(raw.prefix(200))"
            case .moveFailed(let m): return "Failed to move file: \(m)"
            }
        }
    }

    /// Extra context yt-dlp can supply when we've just downloaded from YouTube.
    struct Context: Sendable {
        var uploader: String?
        var channel: String?
        var categories: String?
        var tags: String?
        var playlist: String?

        var isEmpty: Bool {
            uploader == nil && channel == nil && categories == nil
                && tags == nil && playlist == nil
        }
    }

    // MARK: - Classify

    /// Extract canonical artist + clean song from a messy title, optionally
    /// enriched with YouTube metadata and a list of existing artist folders
    /// the new track should reuse when applicable.
    ///
    /// Pure string parsing — no LLM. Handles the patterns yt-dlp / YouTube
    /// titles ship with:
    ///   - "Artist - Song" / "Artist – Song" / "Artist — Song"
    ///   - " [videoId]" suffix yt-dlp appends
    ///   - "(Official Music Video)" / "[HD]" / "(Lyrics)" marketing noise
    /// Falls back to `context.uploader` (yt-dlp's channel/uploader) as
    /// artist when the title has no separator.
    ///
    /// When `existingArtists` includes a case-insensitive match for the
    /// parsed artist (or its uploader fallback), the existing folder name
    /// is reused verbatim — keeps "邓紫棋" / "G.E.M." from creating two
    /// folders for the same person on subsequent downloads.
    static func cleanAndClassify(
        title: String,
        context: Context? = nil,
        existingArtists: [String] = []
    ) async throws -> Cleaned {
        // Try LLM first; fall back to regex parsing on any failure. Failures
        // were previously swallowed by `try?` which made misclassification
        // silently look like the regex was wrong — log so the user can see
        // the AI path actually died.
        do {
            return try await classifyWithAI(
                title: title,
                context: context,
                existingArtists: existingArtists
            )
        } catch {
            print("[MediaCategorizer] AI classify failed for \(title.prefix(80)): \(error.localizedDescription) — falling back to regex")
        }
        return regexClassify(
            title: title,
            context: context,
            existingArtists: existingArtists
        )
    }

    /// LLM classifier. Asks for canonical artist + collaborators + song,
    /// reuses an existing artist folder when one matches.
    static func classifyWithAI(
        title: String,
        context: Context?,
        existingArtists: [String]
    ) async throws -> Cleaned {
        let ai = AIService()
        let system = """
        You extract music metadata from messy YouTube / file titles.
        Return ONLY a JSON object:
        {"artist": "...", "collaborators": ["..."], "song": "..."}

        Rules:
        - "artist" is the primary performer (canonical, native script when applicable: 邓紫棋 not G.E.M.).
        - "collaborators" is the list of OTHER credited artists (feat., &, vs., x, with). Empty array if none.
        - "song" is the clean song / episode title. Strip marketing noise like
          "(Official Music Video)", "[HD]", "(Lyrics)", "[videoId]".
        - When the title doesn't say a performer, fall back to the YouTube uploader / channel.
        - When the user already has a folder for this artist (case-insensitive match
          on any spelling), reuse the EXACT existing folder name verbatim.
        - All fields are strings except "collaborators" which is an array of strings.
        - No markdown fences. No prose. JSON only.
        """

        var lines: [String] = ["Title: \(title)"]
        if let c = context {
            if let v = c.uploader { lines.append("Uploader: \(v)") }
            if let v = c.channel { lines.append("Channel: \(v)") }
            if let v = c.categories { lines.append("Categories: \(v)") }
            if let v = c.tags { lines.append("Tags: \(v)") }
            if let v = c.playlist { lines.append("Playlist: \(v)") }
        }
        if !existingArtists.isEmpty {
            lines.append("Existing artist folders: \(existingArtists.joined(separator: ", "))")
        }

        let raw = try await ai.complete(prompt: lines.joined(separator: "\n"), system: system)
        let trimmed = strippedFences(raw)
        let jsonText: String
        if let r = firstJSONObject(in: trimmed) {
            jsonText = String(trimmed[r])
        } else {
            jsonText = trimmed
        }
        guard let data = jsonText.data(using: .utf8) else {
            throw CategorizeError.invalidJSON(raw)
        }
        struct Resp: Decodable {
            let artist: String?
            let collaborators: [String]?
            let song: String?
        }
        guard let resp = try? JSONDecoder().decode(Resp.self, from: data) else {
            throw CategorizeError.invalidJSON(raw)
        }
        var artist = resp.artist.flatMap { sanitize($0).nonEmpty }
        let song = resp.song.flatMap { sanitize($0).nonEmpty }
        let collaborators = (resp.collaborators ?? []).compactMap { sanitize($0).nonEmpty }

        if let a = artist,
           let match = existingArtists.first(where: { $0.localizedCaseInsensitiveCompare(a) == .orderedSame }) {
            artist = match
        }

        return Cleaned(artist: artist, collaborators: collaborators, song: song)
    }

    /// Original pure-string fallback. Same logic as before — no LLM, no
    /// network. Used when AI is unreachable / disabled.
    static func regexClassify(
        title: String,
        context: Context?,
        existingArtists: [String]
    ) -> Cleaned {
        let stripped = stripNoise(title)

        // Normalize unicode dashes to ASCII " - " before splitting.
        let normalized = stripped
            .replacingOccurrences(of: " — ", with: " - ")  // em dash
            .replacingOccurrences(of: " – ", with: " - ")  // en dash
            .replacingOccurrences(of: " | ", with: " - ")  // pipe (uploader|song)

        var artist: String?
        var song: String?

        let parts = normalized.components(separatedBy: " - ")
        if parts.count >= 2 {
            artist = sanitize(parts[0].trimmingCharacters(in: .whitespaces)).nonEmpty
            song = sanitize(parts.dropFirst().joined(separator: " - ")
                                .trimmingCharacters(in: .whitespaces)).nonEmpty
        } else {
            // No separator — fall back to uploader / channel as artist.
            song = sanitize(normalized.trimmingCharacters(in: .whitespaces)).nonEmpty
            if let u = context?.uploader, let s = sanitize(u).nonEmpty {
                artist = s
            } else if let c = context?.channel, let s = sanitize(c).nonEmpty {
                artist = s
            }
        }

        // Reuse existing folder name when it case-insensitively matches —
        // avoids "邓紫棋" / "邓紫棋 G.E.M." duplicates on next download.
        if let a = artist {
            if let match = existingArtists.first(where: {
                $0.localizedCaseInsensitiveCompare(a) == .orderedSame
            }) {
                artist = match
            }
        }

        return Cleaned(artist: artist, collaborators: [], song: song)
    }

    /// Strip the cruft yt-dlp / YouTube uploaders pile onto titles:
    ///   - " [xxxxxxxxxxx]" 11-char yt-dlp video id suffix
    ///   - " (Official Music Video)", " (Lyric Video)", "[HD]" etc.
    /// Conservative — only matches well-known patterns to avoid eating
    /// real song titles that happen to contain parens.
    static func stripNoise(_ title: String) -> String {
        var s = title

        // yt-dlp video-id tail: \s*\[A-Za-z0-9_-]{11}\]
        if let r = s.range(of: #"\s*\[[A-Za-z0-9_-]{11}\]\s*$"#, options: .regularExpression) {
            s = String(s[..<r.lowerBound])
        }

        // Common marketing tags. Keep `(feat. …)` since users want it.
        let noisePatterns: [String] = [
            #"\s*\((?:Official\s+)?(?:Music\s+)?(?:Video|MV|Audio|Lyrics?|Lyric Video|HD|4K|Performance)\s*\)"#,
            #"\s*\[(?:Official\s+)?(?:Music\s+)?(?:Video|MV|Audio|Lyrics?|Lyric Video|HD|4K)\s*\]"#,
            #"\s*\|\s*Official(?:\s+\w+)*$"#,
        ]
        for pat in noisePatterns {
            while let r = s.range(of: pat, options: [.regularExpression, .caseInsensitive]) {
                s.removeSubrange(r)
            }
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - One-shot organize (used by download path)

    /// Classify + move `url` into `<root>/<Artist>/<filename>`. Returns the
    /// final on-disk URL. Used by the YouTube download pipeline so freshly-
    /// downloaded files land in the right folder immediately.
    @discardableResult
    static func organize(
        url: URL,
        underRoot root: URL,
        preferredTitle: String? = nil,
        context: Context? = nil
    ) async throws -> URL {
        let title = preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? url.deletingPathExtension().lastPathComponent
        let existing = existingFolders(in: root)
        let cleaned = try await cleanAndClassify(
            title: title,
            context: context,
            existingArtists: existing
        )

        let folder = sanitize(cleaned.folderName ?? "").nonEmpty ?? "Unknown"
        let dir = root.appendingPathComponent(folder, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw CategorizeError.moveFailed(error.localizedDescription)
        }

        // Rename: prefer "Artist - Song.ext"; if either is missing, fall
        // back to whichever side parsed cleanly. Original yt-dlp filename
        // (with [videoId] cruft) only used as last resort.
        let ext = url.pathExtension
        let song = cleaned.song.flatMap { sanitize($0).nonEmpty }
        let displayArtist = sanitize(cleaned.folderName ?? "").nonEmpty
        let baseName: String
        if let displayArtist, let song {
            baseName = "\(displayArtist) - \(song)"
        } else if let song {
            baseName = song
        } else {
            baseName = url.deletingPathExtension().lastPathComponent
        }
        let renamedFilename = ext.isEmpty ? baseName : "\(baseName).\(ext)"
        let dest = FileDestinations.unique(for: renamedFilename, in: dir)

        do {
            try FileManager.default.moveItem(at: url, to: dest)
        } catch {
            throw CategorizeError.moveFailed(error.localizedDescription)
        }
        return dest
    }

    /// Recursively flatten input URLs into media files (audio + video) and
    /// run `organize` on each. Returns the final on-disk URLs in completion
    /// order. Used by drop targets that accept files OR folders — dragging a
    /// whole album dir auto-merges into per-artist folders.
    @discardableResult
    static func organizeBatch(
        urls inputs: [URL],
        underRoot root: URL,
        progress: ((String) -> Void)? = nil
    ) async -> [URL] {
        let files = await Task.detached(priority: .userInitiated) {
            expandToMediaFiles(inputs)
        }.value
        var out: [URL] = []
        for (idx, url) in files.enumerated() {
            progress?("Organizing \(idx + 1)/\(files.count): \(url.lastPathComponent)")
            do {
                let dest = try await organize(url: url, underRoot: root)
                out.append(dest)
            } catch {
                progress?("Skip \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        // Best-effort cleanup: remove empty source directories the user dragged in.
        for url in inputs {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [""]
            if contents.filter({ !$0.hasPrefix(".") }).isEmpty {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return out
    }

    nonisolated private static func expandToMediaFiles(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        for url in urls {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                while let next = enumerator?.nextObject() as? URL {
                    let nestedIsDir = (try? next.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if !nestedIsDir, MediaKind.from(url: next) != nil {
                        out.append(next)
                    }
                }
            } else if MediaKind.from(url: url) != nil {
                out.append(url)
            }
        }
        return out
    }

    /// Snapshot of subfolders at `root` — used as context so the LLM reuses
    /// folder names that already exist instead of inventing aliases.
    static func existingFolders(in root: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [String] = []
        for url in entries {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            out.append(url.lastPathComponent)
        }
        return out.sorted()
    }

    // MARK: - Internal

    private static func strippedFences(_ s: String) -> String {
        var out = s
        if out.hasPrefix("```") {
            if let nl = out.firstIndex(of: "\n") {
                out = String(out[out.index(after: nl)...])
            }
        }
        if out.hasSuffix("```") {
            out = String(out.dropLast(3))
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstJSONObject(in s: String) -> Range<String.Index>? {
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var idx = start
        while idx < s.endIndex {
            let ch = s[idx]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return start...idx ~= idx ? start..<s.index(after: idx) : nil }
            }
            idx = s.index(after: idx)
        }
        return nil
    }

    static func sanitize(_ s: String) -> String {
        let badChars: Set<Character> = ["/", ":", "\\", "*", "?", "\"", "<", ">", "|", "\0"]
        var out = s.filter { !badChars.contains($0) }
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        while out.hasPrefix(".") { out.removeFirst() }
        if out.count > 80 { out = String(out.prefix(80)) }
        return out
    }

}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
