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
    /// `existingArtists` is the set of folders already present at the
    /// destination root — the LLM is instructed to pick an exact match from
    /// that list whenever the title describes the same performer, even if
    /// spelled differently (G.E.M. → 邓紫棋).
    static func cleanAndClassify(
        title: String,
        context: Context? = nil,
        existingArtists: [String] = []
    ) async throws -> Cleaned {
        let existingBlock = existingArtists.isEmpty
            ? ""
            : """

            EXISTING ARTIST FOLDERS (reuse exactly one of these names when the
            track is by the same performer — aliases / English-vs-native
            spellings must map onto the existing folder):
            \(existingArtists.map { "- \($0)" }.joined(separator: "\n"))
            """

        let system = LLMMessage(.system, """
        You extract clean metadata for a one-level media library.
        Reply ONLY with strict JSON, no prose, no markdown fence. Schema:
        {
          "artist": "<canonical folder name — see rules, null if truly unknown>",
          "song":   "<clean song / episode title, null if truly unknown>"
        }

        ARTIST RULES — this is the folder name. ONE folder per performer, ever.
        - Output the performer's canonical name. Never invent variants.
        - Prefer the NATIVE-LANGUAGE name. Chinese artists use their Chinese
          name (邓紫棋, 周深, 林俊杰). Japanese artists use 日本語. Korean artists
          use 한글. Western artists use the English stage name.
        - Never store two folders for the same person:
            G.E.M. / Gloria Tang / 邓紫棋  → pick 邓紫棋
            JJ Lin / 林俊杰                → pick 林俊杰
            周深 / Charlie Zhou            → pick 周深
            Taylor Swift / テイラー       → pick Taylor Swift
        - Collabs / duets: join performers with " & ", native names, ordered
          as they appear in the title. e.g. "周深 & 张韶涵", "Taylor Swift &
          Ed Sheeran". Keep unique pairings in their own folders.
        - For podcasts / lectures / audiobooks: use the host / author / course
          name as the artist field (same folder rules).
        - Compilation channels (ZJSTV Music Channel, Vevo, etc.) are NOT the
          artist — parse the real performer from the title.
        - If truly unknown, return null.

        SONG RULES:
        - Strip marketing: "Official MV", "HD", "【】", "Live", track numbers,
          language tags. Keep just the song name.
        - Chinese titles: strip patterns like "纯享丨A+B同台演唱《歌》" —
          the song is what's between 《》.
        - English titles "ARTIST - SONG (feat. X)": song = "SONG".

        Output: strings ASCII-or-CJK only. No slash, colon, backslash, bracket,
        quote in artist. Use null (not "") when unknown.
        \(existingBlock)
        """)

        var userBody = "Title: \(title)"
        if let ctx = context, !ctx.isEmpty {
            if let u = ctx.uploader { userBody += "\nUploader: \(u)" }
            if let c = ctx.channel, c != ctx.uploader { userBody += "\nChannel: \(c)" }
            if let cats = ctx.categories { userBody += "\nYT categories: \(cats)" }
            if let t = ctx.tags { userBody += "\nTags: \(t)" }
            if let p = ctx.playlist { userBody += "\nPlaylist: \(p)" }
        }
        let user = LLMMessage(.user, userBody)

        let provider = AITextService.shared.currentProvider
        let raw = try await provider.generate(
            messages: [system, user],
            parameters: LLMParameters(maxTokens: 200, temperature: 0.15)
        )
        return try parseCleaned(raw)
    }

    private static func parseCleaned(_ raw: String) throws -> Cleaned {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CategorizeError.emptyResponse }
        let stripped = strippedFences(trimmed)
        guard let jsonRange = firstJSONObject(in: stripped),
              let data = String(stripped[jsonRange]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CategorizeError.invalidJSON(stripped) }

        func str(_ key: String) -> String? {
            guard let v = obj[key] as? String else { return nil }
            let t = v.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.lowercased() == "null" || t.lowercased() == "none" { return nil }
            return t
        }
        return Cleaned(
            artist: str("artist"),
            song: str("song")
        )
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

        let dest = FileDestinations.unique(for: url.lastPathComponent, in: dir)
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
