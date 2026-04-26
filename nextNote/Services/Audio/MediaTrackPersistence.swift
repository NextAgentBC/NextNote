import Foundation

/// UserDefaults persistence for the track list. Each track is stored with
/// a security-scoped bookmark so file access survives relaunch — load()
/// resolves bookmarks and returns the URLs we successfully started a
/// scoped access on, so the caller can remember which to release later.
enum MediaTrackPersistence {
    static let key = "mediaLibrary.tracks.v1"

    static func save(_ tracks: [Track]) {
        let entries: [[String: Any]] = tracks.compactMap { t in
            guard let bm = t.bookmark else { return nil }
            return [
                "id": t.id.uuidString,
                "title": t.title,
                "bookmark": bm
            ]
        }
        UserDefaults.standard.set(entries, forKey: key)
    }

    /// Returns the restored tracks plus the set of URLs we acquired a
    /// security-scoped access on. The caller owns those scopes.
    static func load() -> (tracks: [Track], scopedURLs: Set<URL>) {
        var tracks: [Track] = []
        var scoped: Set<URL> = []
        guard let raw = UserDefaults.standard.array(forKey: key) as? [[String: Any]] else {
            return ([], [])
        }
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
                scoped.insert(url)
            }
            tracks.append(Track(id: uuid, url: url, title: title, bookmark: bm))
        }
        return (tracks, scoped)
    }
}
