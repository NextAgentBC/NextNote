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

    // MARK: - Build plan

    static func plan(
        underRoot root: URL,
        library: MediaLibrary
    ) async throws -> Plan {
        // 1. Dead tracks: library record points at non-existent file.
        let dead: [DeadTrackEntry] = library.tracks.compactMap { t in
            FileManager.default.fileExists(atPath: t.url.path)
                ? nil
                : DeadTrackEntry(id: t.id, title: t.title, path: t.url.path)
        }

        // 2. Library duplicates: same file URL referenced by multiple Track
        //    records. Keep the one with the longest title (most metadata).
        let live = library.tracks.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        let byPath = Dictionary(grouping: live, by: { $0.url.standardizedFileURL.path })
        var libDups: [DuplicateLibraryEntry] = []
        for (path, group) in byPath where group.count > 1 {
            let sorted = group.sorted { $0.title.count > $1.title.count }
            libDups.append(DuplicateLibraryEntry(
                path: path,
                trackIDs: sorted.map { $0.id },
                titles: sorted.map { $0.title },
                keepIndex: 0
            ))
        }

        // 3. Disk inventory + library-track inventory union → AI input.
        let folders = listArtistFolders(under: root)
        var inventory: [String: [String]] = [:]
        var emptyFolders: [EmptyFolderEntry] = []
        for folder in folders {
            let dir = root.appendingPathComponent(folder, isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            let media = files
                .filter { !$0.hasPrefix(".") }
                .filter { name in
                    let url = dir.appendingPathComponent(name)
                    return MediaKind.from(url: url) != nil
                }
                .sorted()
            if media.isEmpty {
                emptyFolders.append(EmptyFolderEntry(name: folder))
            } else {
                inventory[folder] = media
            }
        }

        let merges: [ArtistMerge]
        if !inventory.isEmpty {
            merges = (try? await proposeMerges(inventory: inventory, library: library, root: root)) ?? []
        } else {
            merges = []
        }

        // Project the merge mapping over the disk inventory so duplicate
        // detection sees the post-merge artist buckets.
        var folderToCanonical: [String: String] = [:]
        for folder in inventory.keys { folderToCanonical[folder] = folder }
        for m in merges {
            folderToCanonical[m.canonical] = m.canonical
            for a in m.aliases { folderToCanonical[a] = m.canonical }
        }
        var collapsed: [String: [String]] = [:]
        for (folder, files) in inventory {
            let canonical = folderToCanonical[folder] ?? folder
            for f in files { collapsed[canonical, default: []].append("\(folder)/\(f)") }
        }
        let duplicates = detectDuplicates(collapsed: collapsed, root: root)

        return Plan(
            deadTracks: dead,
            duplicateLibraryRecords: libDups,
            emptyFolders: emptyFolders,
            merges: merges,
            duplicates: duplicates
        )
    }

    // MARK: - Apply

    struct Outcome {
        var deadPruned: Int = 0
        var libDupsPruned: Int = 0
        var emptyFoldersRemoved: Int = 0
        var foldersMerged: Int = 0
        var foldersRenamed: Int = 0
        var filesMoved: Int = 0
        var filesRenamed: Int = 0
        var filesTrashed: Int = 0
        var failed: [String] = []
    }

    static func apply(
        _ plan: Plan,
        underRoot root: URL,
        library: MediaLibrary,
        progress: ((String) -> Void)? = nil
    ) async -> Outcome {
        var out = Outcome()

        // Phase 1 — library hygiene (no disk effect).
        for d in plan.deadTracks where d.apply {
            progress?("Removing dead track: \(d.title)")
            library.removeTrack(id: d.id)
            out.deadPruned += 1
        }
        for libDup in plan.duplicateLibraryRecords where libDup.apply {
            for (i, id) in libDup.trackIDs.enumerated() where i != libDup.keepIndex {
                library.removeTrack(id: id)
                out.libDupsPruned += 1
            }
        }

        // Phase 2a — empty / orphan folder cleanup.
        for ef in plan.emptyFolders where ef.apply {
            let dir = root.appendingPathComponent(ef.name, isDirectory: true)
            do {
                try FileManager.default.removeItem(at: dir)
                out.emptyFoldersRemoved += 1
            } catch {
                out.failed.append("\(ef.name)/: \(error.localizedDescription)")
            }
        }

        // Phase 2b — folder merges + renames. Move every file into the
        // canonical folder, rewriting the `<old> - song.ext` prefix to
        // `<new> - song.ext` so filenames stay consistent. When canonical
        // folder is the same as the alias (i.e. a single-folder rename
        // proposal), still go through the move loop so the files get
        // renamed.
        for merge in plan.merges where merge.apply {
            progress?("Reconciling \(merge.canonical)…")
            let canonicalDir = root.appendingPathComponent(merge.canonical, isDirectory: true)
            try? FileManager.default.createDirectory(at: canonicalDir, withIntermediateDirectories: true)

            // Aliases includes the canonical itself only when AI mistakenly
            // listed it (we strip that earlier). For a "rename only" plan,
            // the original folder name shows up as an alias and gets handled
            // here.
            let sourcesToProcess = merge.aliases
            var didChange = false
            for alias in sourcesToProcess {
                let aliasDir = root.appendingPathComponent(alias, isDirectory: true)
                guard FileManager.default.fileExists(atPath: aliasDir.path) else { continue }
                let files = (try? FileManager.default.contentsOfDirectory(atPath: aliasDir.path)) ?? []
                for f in files where !f.hasPrefix(".") {
                    let src = aliasDir.appendingPathComponent(f)
                    let renamed = rewriteFilenamePrefix(f, oldArtist: alias, newArtist: merge.canonical)
                    let dst = FileDestinations.unique(for: renamed, in: canonicalDir)
                    if dst.standardizedFileURL.path == src.standardizedFileURL.path { continue }
                    do {
                        try FileManager.default.moveItem(at: src, to: dst)
                        if renamed != f { out.filesRenamed += 1 } else { out.filesMoved += 1 }
                        if let track = library.tracks.first(where: { $0.url.path == src.path }) {
                            library.updateTrackURL(id: track.id, newURL: dst)
                        }
                        didChange = true
                    } catch {
                        out.failed.append("\(src.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                let remaining = (try? FileManager.default.contentsOfDirectory(atPath: aliasDir.path)) ?? []
                if remaining.filter({ !$0.hasPrefix(".") }).isEmpty {
                    try? FileManager.default.removeItem(at: aliasDir)
                }
            }
            if didChange {
                if sourcesToProcess.count == 1 && sourcesToProcess.first != merge.canonical {
                    out.foldersRenamed += 1
                } else {
                    out.foldersMerged += 1
                }
            }
        }

        // Phase 3 — duplicate trim. Keep the chosen file, trash the rest.
        for dup in plan.duplicates where dup.apply {
            guard dup.relativePaths.indices.contains(dup.keepIndex) else { continue }
            for (i, rel) in dup.relativePaths.enumerated() where i != dup.keepIndex {
                progress?("Trashing duplicate: \(rel)")
                let url = resolvePath(rel, postMergeRoot: root, plan: plan)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                if let track = library.tracks.first(where: { $0.url.path == url.path }) {
                    _ = library.trashTrack(id: track.id)
                    out.filesTrashed += 1
                } else {
                    do {
                        var trashed: NSURL?
                        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
                        out.filesTrashed += 1
                    } catch {
                        out.failed.append("\(rel): \(error.localizedDescription)")
                    }
                }
            }
        }

        return out
    }

    /// Resolve a relative path that might have been moved by a folder merge.
    private static func resolvePath(_ rel: String, postMergeRoot root: URL, plan: Plan) -> URL {
        let original = root.appendingPathComponent(rel)
        if FileManager.default.fileExists(atPath: original.path) { return original }
        let comps = rel.split(separator: "/", maxSplits: 1).map(String.init)
        guard comps.count == 2 else { return original }
        let folder = comps[0]
        let file = comps[1]
        for m in plan.merges where m.apply && m.aliases.contains(folder) {
            return root.appendingPathComponent(m.canonical).appendingPathComponent(file)
        }
        return original
    }

    // MARK: - AI prompts

    /// Send a richer payload: each track's folder + filename + library
    /// display title (when available) so the AI can recognize aliases that
    /// exist only in track titles, not just folder names.
    private static func proposeMerges(
        inventory: [String: [String]],
        library: MediaLibrary,
        root: URL
    ) async throws -> [ArtistMerge] {
        let folders = inventory.keys.sorted()

        // Build per-folder track title list (display titles carry richer
        // artist info than filenames after Restore Titles runs).
        var folderTitles: [String: [String]] = [:]
        for track in library.tracks {
            let parent = track.url.deletingLastPathComponent().standardizedFileURL.path
            let rootStd = root.standardizedFileURL.path
            guard parent.hasPrefix(rootStd) else { continue }
            let folder = track.url.deletingLastPathComponent().lastPathComponent
            folderTitles[folder, default: []].append(track.title)
        }

        let ai = AIService()
        let system = """
        You audit a music-library artist-folder set. Your job is two-fold:
          1. MERGE folders whose performers are the same person spelled
             differently (G.E.M. + 邓紫棋, Jay Chou + 周杰伦).
          2. RENAME single folders to the canonical native-script name even
             when no merge target currently exists. Example: only "Jay Chou"
             folder exists → propose canonical "周杰伦", aliases ["Jay Chou"].

        Also flag folders whose name is NOT a performer (e.g. a song title,
        a video category, "MusicRelax"). Look at the sample tracks under
        each folder. If the tracks are by a clear performer, propose the
        rename. If unclear, skip — leave the folder alone.

        Return ONLY JSON:
        {
          "merges": [
            { "canonical": "...", "aliases": ["...", "..."] }
          ]
        }

        Rules:
        - "canonical" can be ANY string — does NOT need to be one of the
          input folder names. Use native script (Chinese / Japanese / Korean
          over romanized).
        - "aliases" MUST be EXACT folder names from the input. List EVERY
          folder that should map to the canonical (including the original
          folder when it's a pure rename — "Jay Chou" should appear in
          aliases when canonical is "周杰伦").
        - Do NOT merge collabs. "A & B" stays separate from "A" and from
          "B" — collabs are their own thing.
        - Skip folders whose tracks are non-music tutorials (e.g. "The
          Organic Chemistry Tutor"). Don't propose changes for those.
        - Empty "merges" array if nothing needs to change.
        - No prose. JSON only, no markdown fences.
        """

        var payload: [String] = []
        payload.append("Existing artist folders + sample tracks under each:")
        for folder in folders {
            let files = inventory[folder] ?? []
            let titles = folderTitles[folder] ?? []
            let samples = (titles + files).prefix(6).joined(separator: " | ")
            payload.append("- \(folder)  →  \(samples)")
        }

        let raw = try await ai.complete(prompt: payload.joined(separator: "\n"), system: system)
        let json = extractJSON(raw)
        struct Resp: Decodable {
            struct M: Decodable { let canonical: String; let aliases: [String] }
            let merges: [M]
        }
        guard let data = json.data(using: .utf8),
              let resp = try? JSONDecoder().decode(Resp.self, from: data) else {
            throw ReconcileError.invalidJSON(raw)
        }
        let validNames = Set(folders)
        return resp.merges.compactMap { m in
            // Aliases must reference real folders. Canonical can be a new
            // name (rename target) — no need to be in `folders`.
            let aliases = m.aliases.filter { validNames.contains($0) && $0 != m.canonical }
            guard !aliases.isEmpty,
                  !m.canonical.trimmingCharacters(in: .whitespaces).isEmpty
            else { return nil }
            return ArtistMerge(canonical: m.canonical, aliases: aliases)
        }
    }

    /// Pure-string duplicate detection — same artist bucket + normalized
    /// song stem. Cheap, runs over every collapsed bucket. Doesn't catch
    /// remix/cover variants — that requires a follow-up AI pass.
    private static func detectDuplicates(collapsed: [String: [String]], root: URL) -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []
        for (artist, paths) in collapsed where paths.count > 1 {
            let songs = paths.map { ($0, songStem(from: $0)) }
            let buckets = Dictionary(grouping: songs, by: { normalizeSongKey($0.1) })
            for (key, items) in buckets where items.count > 1 {
                let rels = items.map { $0.0 }
                let keepIdx = pickKeeperIndex(relativePaths: rels, root: root)
                groups.append(DuplicateGroup(
                    artist: artist,
                    song: items.first?.1 ?? key,
                    relativePaths: rels,
                    keepIndex: keepIdx
                ))
            }
        }
        return groups.sorted { ($0.artist, $0.song) < ($1.artist, $1.song) }
    }

    /// Largest file size wins.
    private static func pickKeeperIndex(relativePaths: [String], root: URL) -> Int {
        var bestIdx = 0
        var bestSize: Int64 = -1
        for (i, rel) in relativePaths.enumerated() {
            let url = root.appendingPathComponent(rel)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            if size > bestSize { bestSize = size; bestIdx = i }
        }
        return bestIdx
    }

    /// Rewrite the artist-prefix portion of a filename when its parent
    /// folder gets renamed. Looks for `<oldArtist> - ` or `<oldArtist> — `
    /// at the start of the filename and substitutes the canonical name.
    /// Returns the original filename when no prefix match.
    private static func rewriteFilenamePrefix(_ filename: String, oldArtist: String, newArtist: String) -> String {
        let separators = [" - ", " — ", " – "]
        for sep in separators {
            let prefix = "\(oldArtist)\(sep)"
            if filename.hasPrefix(prefix) {
                let rest = String(filename.dropFirst(prefix.count))
                return "\(newArtist)\(sep)\(rest)"
            }
        }
        return filename
    }

    // MARK: - Helpers

    private static func listArtistFolders(under root: URL) -> [String] {
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

    private static func songStem(from relativePath: String) -> String {
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
    private static func normalizeSongKey(_ s: String) -> String {
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

    private static func extractJSON(_ raw: String) -> String {
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
