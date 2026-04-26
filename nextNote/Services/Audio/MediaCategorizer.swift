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
        var artist: String?      // canonical folder name, prefer native script
        var song: String?        // clean song / episode title, no marketing noise
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

        return Cleaned(artist: artist, song: song)
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

        let folder = sanitize(cleaned.artist ?? "").nonEmpty ?? "Unknown"
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
        let cleanArtist = cleaned.artist.flatMap { sanitize($0).nonEmpty }
        let baseName: String
        if let cleanArtist, let song {
            baseName = "\(cleanArtist) - \(song)"
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
