import Foundation

/// AI-driven library reconciliation. Three passes:
///   1. **Dead-track prune** — library track whose file no longer exists on
///      disk gets removed from the library index.
///   2. **Library URL dedup** — multiple library records pointing at the
///      same on-disk file collapse to one.
///   3. **AI plan** — given full track inventory (title + folder + path),
///      LLM returns artist-folder merges + duplicate sets across folders.
///
/// The user reviews the plan in `LibraryReconcileSheet` then applies it.
///
/// This file holds the data shapes (`Plan` + sub-types, `ReconcileError`,
/// `Outcome`) and small disk/string helpers. The two extensions split the
/// actual work: `+Plan.swift` builds the plan (incl. AI calls);
/// `+Apply.swift` executes it against disk + library.
@MainActor
enum LibraryReconciler {

    // MARK: - Plan types

    struct ArtistMerge: Identifiable, Equatable {
        let id = UUID()
        var canonical: String
        var aliases: [String]
        var apply: Bool = true
    }

    struct DuplicateGroup: Identifiable, Equatable {
        let id = UUID()
        var artist: String
        var song: String
        /// Files in this duplicate group, relative to mediaRoot.
        var relativePaths: [String]
        /// Index into `relativePaths` of the file to KEEP. Largest by default.
        var keepIndex: Int
        var apply: Bool = true
    }

    /// Library-only fix: track UUIDs whose URL.path has no file on disk.
    struct DeadTrackEntry: Identifiable, Equatable {
        let id: UUID
        var title: String
        var path: String
        var apply: Bool = true
    }

    /// Library-only fix: multiple Track records pointing at the same path.
    struct DuplicateLibraryEntry: Identifiable, Equatable {
        let id = UUID()
        var path: String
        var trackIDs: [UUID]
        var titles: [String]
        var keepIndex: Int = 0
        var apply: Bool = true
    }

    /// Empty / orphan folder. No media files inside. Safe to delete.
    struct EmptyFolderEntry: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var apply: Bool = true
    }

    struct Plan: Equatable {
        var deadTracks: [DeadTrackEntry]
        var duplicateLibraryRecords: [DuplicateLibraryEntry]
        var emptyFolders: [EmptyFolderEntry]
        var merges: [ArtistMerge]
        var duplicates: [DuplicateGroup]

        var isEmpty: Bool {
            deadTracks.isEmpty
                && duplicateLibraryRecords.isEmpty
                && emptyFolders.isEmpty
                && merges.isEmpty
                && duplicates.isEmpty
        }
    }

    enum ReconcileError: LocalizedError {
        case noRoot
        case aiFailed(String)
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .noRoot: return "Media library root is not configured."
            case .aiFailed(let m): return "AI request failed: \(m)"
            case .invalidJSON(let raw): return "AI response wasn't valid JSON:\n\(raw.prefix(200))"
            }
        }
    }

    // MARK: - Helpers (used by both +Plan and +Apply siblings)

    static func listArtistFolders(under root: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.compactMap { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDir ? url.lastPathComponent : nil
        }
    }

    static func songStem(from relativePath: String) -> String {
        let comps = relativePath.split(separator: "/").map(String.init)
        let file = comps.last ?? relativePath
        let stem = (file as NSString).deletingPathExtension
        if let dash = stem.range(of: " - ") {
            return String(stem[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if let dash = stem.range(of: " — ") {
            return String(stem[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return stem
    }

    /// Lowercase + drop punctuation/whitespace. Strip yt-dlp `(2)` /
    /// `[videoId]` tails so "Mojito" / "Mojito (2)" / "Mojito [abc]" match.
    static func normalizeSongKey(_ s: String) -> String {
        var t = s.lowercased()
        // Drop yt-dlp video-id `[xxxxxxxxxxx]`
        t = t.replacingOccurrences(of: #"\s*\[[a-z0-9_-]{11}\]\s*"#,
                                   with: "", options: .regularExpression)
        // Drop "(2)", "(remix)" only when they're at the end? Actually keep
        // pure parens-content out of the key entirely so "Mojito (Remix)" and
        // "Mojito" collapse — user gets to review and keep/reject.
        t = t.replacingOccurrences(of: #"\s*\([^\)]*\)\s*"#, with: "", options: .regularExpression)
        let stripped = t.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
                || CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}").contains($0)
                || CharacterSet(charactersIn: "\u{3040}"..."\u{30FF}").contains($0)
                || CharacterSet(charactersIn: "\u{AC00}"..."\u{D7AF}").contains($0)
        }
        return String(String.UnicodeScalarView(stripped))
    }

    static func extractJSON(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let nl = s.firstIndex(of: "\n") { s = String(s[s.index(after: nl)...]) }
            if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        }
        if let start = s.firstIndex(of: "{"),
           let end = s.lastIndex(of: "}"), start < end {
            return String(s[start...end])
        }
        return s
    }
}
