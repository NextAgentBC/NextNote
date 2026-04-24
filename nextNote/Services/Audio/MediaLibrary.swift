import Foundation
import Combine
import AppKit

// App-wide audio library. Owns the master list of tracks (each with a
// security-scoped bookmark so access survives relaunch) and the set of
// user-created playlists.
//
// Playback is driven by AmbientPlayer, which the library pushes queues into
// on demand — the library itself doesn't play anything.
@MainActor
final class MediaLibrary: ObservableObject {
    static let shared = MediaLibrary()

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var ambientFolderURL: URL?
    @Published private(set) var isScanning: Bool = false

    /// A single collapsible group in the sidebar — one per parent folder
    /// under the scan root.
    struct MediaGroup: Identifiable, Hashable {
        var id: String { "\(kind.rawValue)/\(folder)" }
        var folder: String
        var kind: MediaKind
        var items: [Track]
    }

    private var scopedURLs: Set<URL> = []
    private var ambientFolderScope: URL?

    private static let tracksKey = "mediaLibrary.tracks.v1"
    private static let playlistsKey = "mediaLibrary.playlists.v1"
    private static let ambientFolderKey = "mediaLibrary.ambientFolder.bookmark"
    private static let promptedFlagKey = "mediaLibrary.hasPromptedAmbientFolder"

    /// True once the user has answered the first-launch prompt (either
    /// picking a folder or declining). Used to suppress the prompt on
    /// subsequent launches.
    var hasPromptedForAmbientFolder: Bool {
        UserDefaults.standard.bool(forKey: Self.promptedFlagKey)
    }

    /// True when the prompt should be shown this launch: we haven't asked
    /// before, and no folder has been set.
    var shouldPromptForAmbientFolder: Bool {
        !hasPromptedForAmbientFolder && ambientFolderURL == nil
    }

    func markPrompted() {
        UserDefaults.standard.set(true, forKey: Self.promptedFlagKey)
    }

    private init() {
        restoreTracks()
        restorePlaylists()
        restoreAmbientFolder()
        // Drop tracks whose file vanished since last launch (deleted in
        // Finder, external drive gone, vault cleared, etc). Keeps the
        // library from resurrecting ghost entries through stale bookmarks.
        _ = pruneMissing()
    }

    deinit {
        for url in scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        ambientFolderScope?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Ambient folder (first-launch library root)

    /// Show NSOpenPanel to pick a persistent folder for ambient media. Saves
    /// a security-scoped bookmark, kicks off a recursive scan that auto-adds
    /// any audio/video it finds. Returns true if the user picked something.
    @discardableResult
    func pickAmbientFolder() async -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Pick a long-term folder for your ambient music and video library. Contents will be auto-added, and future downloads get organized under it."

        let resp = await withCheckedContinuation { (cont: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { cont.resume(returning: $0) }
            } else {
                cont.resume(returning: panel.runModal())
            }
        }
        guard resp == .OK, let url = panel.url else { return false }
        adoptAmbientFolder(url)
        markPrompted()
        await scanAmbientFolder()
        return true
    }

    private func adoptAmbientFolder(_ url: URL) {
        ambientFolderScope?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else { return }
        ambientFolderScope = url
        ambientFolderURL = url
        let bm = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bm, forKey: Self.ambientFolderKey)
    }

    private func restoreAmbientFolder() {
        guard let data = UserDefaults.standard.data(forKey: Self.ambientFolderKey) else { return }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return }
        if url.startAccessingSecurityScopedResource() {
            ambientFolderScope = url
        }
        ambientFolderURL = url
    }

    /// Walk the ambient folder recursively, add every audio/video file not
    /// already in the library. Bookmarks are created under the folder's
    /// security scope (which we hold open from adoptAmbientFolder /
    /// restoreAmbientFolder).
    func scanAmbientFolder() async {
        guard let root = ambientFolderURL else { return }
        _ = pruneMissing()
        let found = Self.walkForMedia(root: root)
        // addFiles does its own dedupe-by-path.
        _ = addFiles(found)
    }

    /// Scan an arbitrary root (the vault's Media library root). Drops tracks
    /// that live *under* this root and no longer exist, leaves tracks from
    /// other roots alone, and ingests any new files it finds. This is the
    /// single entry point the sidebar + ContentView use — keeps the sidebar
    /// tree and the Media Library popup reading from the same @Published
    /// `tracks` list, so a rename / remove / add in one UI is live-visible
    /// in the other.
    func scanRoot(_ root: URL?) async {
        guard let root else { return }
        isScanning = true
        defer { isScanning = false }

        let rootPath = root.standardizedFileURL.path
        let missingUnderRoot = tracks
            .filter { $0.url.standardizedFileURL.path.hasPrefix(rootPath) }
            .filter { !FileManager.default.fileExists(atPath: $0.url.path) }
        if !missingUnderRoot.isEmpty {
            removeTracks(ids: Set(missingUnderRoot.map { $0.id }))
        }

        let found = Self.walkForMedia(root: root)
        _ = addFiles(found)
    }

    // MARK: - Grouping for sidebar

    /// Tracks of `kind` grouped by their first-level folder under `root`.
    /// Sorted alphabetically with "loose" files last. The sidebar + popup
    /// share this derivation, so they stay in sync automatically.
    func groups(kind: MediaKind, under root: URL?) -> [MediaGroup] {
        let rootPath = root?.standardizedFileURL.path
        let filtered = tracks.filter { MediaKind.from(url: $0.url) == kind }
        var bucket: [String: [Track]] = [:]
        for t in filtered {
            let folder = Self.firstLevelFolder(of: t.url, under: rootPath)
            bucket[folder, default: []].append(t)
        }
        let orderedKeys = bucket.keys.sorted { a, b in
            if a.isEmpty { return false }
            if b.isEmpty { return true }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        return orderedKeys.map { key in
            let items = (bucket[key] ?? []).sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return MediaGroup(folder: key, kind: kind, items: items)
        }
    }

    /// First directory component under `rootPath` — e.g. a file at
    /// `<root>/邓紫棋/song.mp3` becomes `"邓紫棋"`. Files directly at the
    /// root (or outside it) get `""` so callers can render them under an
    /// "Uncategorized" heading.
    private static func firstLevelFolder(of file: URL, under rootPath: String?) -> String {
        guard let rootPath else { return "" }
        let full = file.standardizedFileURL.path
        guard full.hasPrefix(rootPath) else { return "" }
        var rel = String(full.dropFirst(rootPath.count))
        if rel.hasPrefix("/") { rel.removeFirst() }
        let segments = rel.split(separator: "/", omittingEmptySubsequences: true)
        if segments.count <= 1 { return "" }
        return String(segments[0])
    }

    // Synchronous helper — FileManager.enumerator's NSEnumerator makeIterator
    // is @preconcurrency-banned in async contexts under Swift 6 strict mode,
    // so we do the walk non-async and hand back a plain array.
    private nonisolated static func walkForMedia(root: URL) -> [URL] {
        let fm = FileManager.default
        var found: [URL] = []
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return found }
        for case let url as URL in enumerator {
            if MediaKind.from(url: url) != nil { found.append(url) }
        }
        return found
    }

    // MARK: - Track CRUD

    /// Add files to the library. Dedupes by URL path. Returns the newly added
    /// tracks (in file order) — useful for the caller to enqueue immediately.
    @discardableResult
    func addFiles(_ urls: [URL]) -> [Track] {
        urls.compactMap { addFile(url: $0, title: nil, artist: nil) }
    }

    /// Register a single file with an explicit title/artist pair. Used by the
    /// YouTube downloader so display titles come from yt-dlp metadata instead
    /// of the filename (which is already "artist - title [id]" but we want a
    /// cleaner "artist — title" in the UI without the id suffix).
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
        let displayTitle = Self.buildDisplayTitle(
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

    /// "邓紫棋 — 光年之外" when both parts known; fall back progressively to
    /// title-only, then to the cleaned-up filename.
    private static func buildDisplayTitle(explicit: String?, artist: String?, fallbackURL: URL) -> String {
        let clean = { (s: String?) -> String? in
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        let t = clean(explicit)
        let a = clean(artist)
        if let a, let t { return "\(a) — \(t)" }
        if let t { return t }
        if let a { return a }
        // Last-ditch: filename, but strip the " [videoId]" yt-dlp suffix so
        // folder-scan imports of existing downloads still look readable.
        let raw = fallbackURL.deletingPathExtension().lastPathComponent
        return Self.stripYouTubeIDSuffix(raw)
    }

    private static func stripYouTubeIDSuffix(_ s: String) -> String {
        // Matches a trailing " [xxxxxxxxxxx]" where the id is 11 chars of
        // YouTube's base64-ish alphabet. Non-YT filenames pass through.
        let pattern = #"\s*\[[A-Za-z0-9_-]{11}\]\s*$"#
        if let range = s.range(of: pattern, options: .regularExpression) {
            return String(s[..<range.lowerBound])
        }
        return s
    }

    /// Re-point an existing track at a new on-disk URL (e.g., after the
    /// categorizer moved the file). Preserves the track UUID so any playlist
    /// references stay valid. Refreshes the security-scoped bookmark. Pass a
    /// `newTitle` to simultaneously update the display name (YT backfill
    /// pipeline uses this to rename + rebrand in one step).
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
        tracks[idx] = Track(
            id: old.id,
            url: newURL,
            title: newTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? old.title,
            bookmark: bookmark
        )
        persistTracks()
    }

    /// Rename a track's display title (UI only — file on disk is untouched).
    func renameTrack(id: UUID, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = tracks.firstIndex(where: { $0.id == id }) else { return }
        let t = tracks[idx]
        tracks[idx] = Track(id: t.id, url: t.url, title: trimmed, bookmark: t.bookmark)
        persistTracks()
    }

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

    /// Rename the track's on-disk file. `newBaseName` is the filename WITHOUT
    /// extension — original extension is preserved. Updates URL + bookmark +
    /// scopedURLs in lockstep. Does NOT touch the display title (caller can
    /// follow up with renameTrack if desired).
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

    /// Batch-remove tracks from the library. Also stops the AmbientPlayer if
    /// one of them is currently playing, purges them from the player queue,
    /// and cleans them out of any playlist references.
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

    /// Drop any tracks whose underlying file no longer exists on disk (user
    /// deleted it in Finder, moved the external drive, etc). Also stops the
    /// player if it was playing one of them.
    @discardableResult
    func pruneMissing() -> Int {
        let missing = tracks.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
        guard !missing.isEmpty else { return 0 }
        removeTracks(ids: Set(missing.map { $0.id }))
        return missing.count
    }

    /// Move a track's on-disk file to the Trash AND remove it from the library.
    /// Used by the UI's "Move to Trash" action. Returns true on success.
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

    // MARK: - Playlist CRUD

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

    /// Scan a folder tree and (re-)generate one playlist per sub-folder that
    /// directly contains media. AI is used to clean up folder names into
    /// title-case playlist names. Existing playlists whose `sourceFolder`
    /// matches are updated in place (new track IDs appended, name refreshed);
    /// brand-new folders get a freshly created playlist.
    ///
    /// Returns (created, updated) count for UI feedback.
    @discardableResult
    func generatePlaylistsFromFolders(
        root: URL,
        useAI: Bool = true,
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
                    sampleTitles: Array(samples)
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

    /// Resolve a playlist's track IDs back to concrete tracks, skipping any
    /// IDs that no longer exist in the library.
    func tracks(in playlist: Playlist) -> [Track] {
        playlist.trackIDs.compactMap { id in tracks.first(where: { $0.id == id }) }
    }

    // MARK: - Persistence

    private func persistTracks() {
        let entries: [[String: Any]] = tracks.compactMap { t in
            guard let bm = t.bookmark else { return nil }
            return [
                "id": t.id.uuidString,
                "title": t.title,
                "bookmark": bm
            ]
        }
        UserDefaults.standard.set(entries, forKey: Self.tracksKey)
    }

    private func persistPlaylists() {
        let entries: [[String: Any]] = playlists.map { p in
            var e: [String: Any] = [
                "id": p.id.uuidString,
                "name": p.name,
                "trackIDs": p.trackIDs.map { $0.uuidString }
            ]
            if let src = p.sourceFolder { e["sourceFolder"] = src }
            return e
        }
        UserDefaults.standard.set(entries, forKey: Self.playlistsKey)
    }

    private func restoreTracks() {
        guard let raw = UserDefaults.standard.array(forKey: Self.tracksKey) as? [[String: Any]]
        else { return }
        for entry in raw {
            guard let bm = entry["bookmark"] as? Data,
                  let idStr = entry["id"] as? String,
                  let uuid = UUID(uuidString: idStr),
                  let title = entry["title"] as? String
            else { continue }
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: bm,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            if url.startAccessingSecurityScopedResource() {
                scopedURLs.insert(url)
            }
            tracks.append(Track(id: uuid, url: url, title: title, bookmark: bm))
        }
    }

    private func restorePlaylists() {
        guard let raw = UserDefaults.standard.array(forKey: Self.playlistsKey) as? [[String: Any]]
        else { return }
        for entry in raw {
            guard let idStr = entry["id"] as? String,
                  let uuid = UUID(uuidString: idStr),
                  let name = entry["name"] as? String,
                  let idsRaw = entry["trackIDs"] as? [String]
            else { continue }
            let ids = idsRaw.compactMap { UUID(uuidString: $0) }
            let source = entry["sourceFolder"] as? String
            playlists.append(Playlist(id: uuid, name: name, trackIDs: ids, sourceFolder: source))
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
