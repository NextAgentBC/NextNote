import Foundation

// Build a reconciliation `Plan` — the read-only audit pass. Combines three
// sources: dead library tracks (record without file), duplicate library
// records (multiple records pointing at one file), and an AI-proposed
// folder-merge + cross-folder duplicate-set pass over the on-disk inventory.
extension LibraryReconciler {

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
}
