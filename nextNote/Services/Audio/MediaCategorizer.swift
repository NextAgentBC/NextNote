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
        // Parse "Artist - Song" pattern if present; otherwise use title as song.
        let parts = title.components(separatedBy: " - ")
        if parts.count >= 2 {
            return Cleaned(
                artist: sanitize(parts[0].trimmingCharacters(in: .whitespaces)).nonEmpty,
                song: parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces).nonEmpty
            )
        }
        return Cleaned(artist: nil, song: title.trimmingCharacters(in: .whitespaces).nonEmpty)
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
