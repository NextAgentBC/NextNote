import Foundation

extension MediaLibrary {
    enum RenameFileError: LocalizedError {
        case invalidName
        case destinationExists(String)
        case moveFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidName: return "Filename can't be empty or contain path separators."
            case .destinationExists(let n): return "A file named \"\(n)\" already exists in that folder."
            case .moveFailed(let m): return "Rename failed: \(m)"
            }
        }
    }

    /// Add files to the library. Dedupes by URL path. Returns the newly
    /// added tracks (in file order) — useful for the caller to enqueue
    /// immediately.
    @discardableResult
    func addFiles(_ urls: [URL]) -> [Track] {
        urls.compactMap { addFile(url: $0, title: nil, artist: nil) }
    }

    /// Register a single file with an explicit title/artist pair. Used by
    /// the YouTube downloader so display titles come from yt-dlp metadata
    /// instead of the filename.
    @discardableResult
    func addFile(url: URL, title: String?, artist: String?) -> Track? {
        guard MediaKind.from(url: url) != nil else { return nil }
        if let existing = tracks.first(where: { $0.url.path == url.path }) {
            return existing
        }
        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        if url.startAccessingSecurityScopedResource() {
            scopedURLs.insert(url)
        }
        let displayTitle = TrackTitleFormatter.displayTitle(
            explicit: title,
            artist: artist,
            fallbackURL: url
        )
        let track = Track(
            id: UUID(),
            url: url,
            title: displayTitle,
            bookmark: bookmark
        )
        tracks.append(track)
        persistTracks()
        return track
    }

    /// Re-point an existing track at a new on-disk URL (e.g., after the
    /// categorizer moved the file). Preserves the track UUID so any
    /// playlist references stay valid. Refreshes the security-scoped
    /// bookmark. Pass a `newTitle` to simultaneously update the display
    /// name (YT backfill pipeline uses this to rename + rebrand in one
    /// step).
    func updateTrackURL(id: UUID, newURL: URL, newTitle: String? = nil) {
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        let old = tracks[idx]
        if scopedURLs.contains(old.url) {
            old.url.stopAccessingSecurityScopedResource()
            scopedURLs.remove(old.url)
        }
        let bookmark = try? newURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        if newURL.startAccessingSecurityScopedResource() {
            scopedURLs.insert(newURL)
        }
        let trimmedTitle = newTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (trimmedTitle?.isEmpty == false ? trimmedTitle! : old.title)
        tracks[idx] = Track(
            id: old.id,
            url: newURL,
            title: resolvedTitle,
            bookmark: bookmark
        )
        persistTracks()
    }

    /// Rename a track's display title (UI only — file on disk untouched).
    func renameTrack(id: UUID, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        let t = tracks[idx]
        tracks[idx] = Track(id: t.id, url: t.url, title: trimmed, bookmark: t.bookmark)
        persistTracks()
    }

    /// Rename the track's on-disk file. `newBaseName` is the filename
    /// WITHOUT extension — original extension preserved. Updates URL +
    /// bookmark + scopedURLs in lockstep. Does NOT touch the display
    /// title (caller can follow up with renameTrack if desired).
    func renameTrackFile(id: UUID, newBaseName: String) throws {
        let clean = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              !clean.contains("/"),
              !clean.contains(":"),
              !clean.contains("\\") else { throw RenameFileError.invalidName }
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        let old = tracks[idx]
        let dir = old.url.deletingLastPathComponent()
        let ext = old.url.pathExtension
        let newName = ext.isEmpty ? clean : "\(clean).\(ext)"
        let newURL = dir.appendingPathComponent(newName)

        if newURL.path == old.url.path { return }
        if FileManager.default.fileExists(atPath: newURL.path) {
            throw RenameFileError.destinationExists(newName)
        }
        do {
            try FileManager.default.moveItem(at: old.url, to: newURL)
        } catch {
            throw RenameFileError.moveFailed(error.localizedDescription)
        }
        updateTrackURL(id: id, newURL: newURL)
    }

    func removeTrack(id: UUID) {
        removeTracks(ids: [id])
    }

    /// Batch-remove tracks from the library. Also stops the AmbientPlayer
    /// if one of them is currently playing, purges them from the player
    /// queue, and cleans them out of any playlist references.
    func removeTracks(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        AmbientPlayer.shared.removeTracks(withIDs: ids)
        for id in ids {
            guard let idx = tracks.firstIndex(where: { $0.id == id }) else { continue }
            let track = tracks.remove(at: idx)
            if scopedURLs.contains(track.url) {
                track.url.stopAccessingSecurityScopedResource()
                scopedURLs.remove(track.url)
            }
        }
        for i in playlists.indices {
            playlists[i].trackIDs.removeAll { ids.contains($0) }
        }
        persistTracks()
        persistPlaylists()
    }

    /// Drop any tracks whose underlying file no longer exists on disk
    /// (user deleted in Finder, moved external drive, etc). Also stops
    /// the player if it was playing one of them.
    @discardableResult
    func pruneMissing() -> Int {
        let missing = tracks.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
        guard !missing.isEmpty else { return 0 }
        removeTracks(ids: Set(missing.map { $0.id }))
        return missing.count
    }

    /// Move a track's on-disk file to the Trash AND remove it from the
    /// library. Used by the UI's "Move to Trash" action. Returns true
    /// on success.
    @discardableResult
    func trashTrack(id: UUID) -> Bool {
        guard let idx = tracks.firstIndex(where: { $0.id == id }) else { return false }
        let url = tracks[idx].url
        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        } catch {
            NSLog("[MediaLibrary] trashItem failed for \(url.path): \(error)")
            return false
        }
        removeTrack(id: id)
        return true
    }

    func track(id: UUID) -> Track? {
        tracks.first(where: { $0.id == id })
    }
}
