import Foundation

extension MediaLibrary {
    @discardableResult
    func createPlaylist(name: String) -> Playlist {
        let p = Playlist(id: UUID(), name: name, trackIDs: [])
        playlists.append(p)
        persistPlaylists()
        return p
    }

    func renamePlaylist(id: UUID, to name: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[idx].name = name
        persistPlaylists()
    }

    func deletePlaylist(id: UUID) {
        playlists.removeAll { $0.id == id }
        persistPlaylists()
    }

    func addToPlaylist(_ playlistID: UUID, trackIDs ids: [UUID]) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let existing = Set(playlists[idx].trackIDs)
        for tid in ids where !existing.contains(tid) {
            playlists[idx].trackIDs.append(tid)
        }
        persistPlaylists()
    }

    func removeFromPlaylist(_ playlistID: UUID, at offsets: IndexSet) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[idx].trackIDs.remove(atOffsets: offsets)
        persistPlaylists()
    }

    func movePlaylistTracks(_ playlistID: UUID, from: IndexSet, to: Int) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[idx].trackIDs.move(fromOffsets: from, toOffset: to)
        persistPlaylists()
    }

    /// Scan a folder tree and (re-)generate one playlist per sub-folder
    /// that directly contains media. AI is used to clean up folder names
    /// into title-case playlist names. Existing playlists whose
    /// `sourceFolder` matches are updated in place (new track IDs
    /// appended, name refreshed); brand-new folders get a freshly
    /// created playlist. Returns (created, updated) for UI feedback.
    @discardableResult
    func generatePlaylistsFromFolders(
        root: URL,
        useAI: Bool = true,
        ai: AIService? = nil,
        excludes: Set<String> = PlaylistSynth.defaultExcludes,
        onStatus: @MainActor @escaping (String) -> Void = { _ in }
    ) async -> (created: Int, updated: Int) {
        onStatus("Scanning \(root.lastPathComponent)…")
        NSLog("[MediaLibrary] Generating playlists from \(root.path), ambientFolderURL=\(ambientFolderURL?.path ?? "nil")")
        let candidates = PlaylistSynth.scan(root: root, excludes: excludes)
        NSLog("[MediaLibrary] scan found \(candidates.count) candidate folders: \(candidates.map { $0.folderName })")
        guard !candidates.isEmpty else {
            onStatus("No media folders found at \(root.path).")
            return (0, 0)
        }
        onStatus("Found \(candidates.count) folders. Processing…")

        var created = 0
        var updated = 0

        for candidate in candidates {
            onStatus("Processing \(candidate.folderName) (\(candidate.mediaURLs.count) items)…")

            // Make sure every media URL is registered before we assign IDs.
            _ = addFiles(candidate.mediaURLs)
            let pathSet = Set(candidate.mediaURLs.map { $0.path })
            let trackIDs = tracks
                .filter { pathSet.contains($0.url.path) }
                .map { $0.id }

            // AI-cleaned name, or raw folder name on skip/failure.
            let finalName: String
            if useAI {
                let samples = candidate.mediaURLs.prefix(5).map {
                    $0.deletingPathExtension().lastPathComponent
                }
                finalName = await PlaylistSynth.suggestName(
                    folderName: candidate.folderName,
                    sampleTitles: Array(samples),
                    ai: ai
                )
            } else {
                finalName = candidate.folderName
            }

            // Update-in-place if we already have a playlist for this folder.
            if let idx = playlists.firstIndex(where: { $0.sourceFolder == candidate.folderPath }) {
                playlists[idx].name = finalName
                // Preserve user reordering but fold in any newly added tracks.
                let existing = Set(playlists[idx].trackIDs)
                for tid in trackIDs where !existing.contains(tid) {
                    playlists[idx].trackIDs.append(tid)
                }
                updated += 1
            } else {
                playlists.append(Playlist(
                    id: UUID(),
                    name: finalName,
                    trackIDs: trackIDs,
                    sourceFolder: candidate.folderPath
                ))
                created += 1
            }
        }

        persistPlaylists()
        onStatus("Done — \(created) created, \(updated) updated.")
        return (created, updated)
    }

    /// Resolve a playlist's track IDs back to concrete tracks, skipping
    /// any IDs that no longer exist in the library.
    func tracks(in playlist: Playlist) -> [Track] {
        playlist.trackIDs.compactMap { id in tracks.first(where: { $0.id == id }) }
    }
}
