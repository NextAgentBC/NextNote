import Foundation

/// UserDefaults persistence for the playlist list. Playlists carry only
/// references (UUIDs), so unlike tracks no bookmark resolution is needed.
enum PlaylistPersistence {
    static let key = "mediaLibrary.playlists.v1"

    static func save(_ playlists: [Playlist]) {
        let entries: [[String: Any]] = playlists.map { p in
            var e: [String: Any] = [
                "id": p.id.uuidString,
                "name": p.name,
                "trackIDs": p.trackIDs.map { $0.uuidString }
            ]
            if let src = p.sourceFolder { e["sourceFolder"] = src }
            return e
        }
        UserDefaults.standard.set(entries, forKey: key)
    }

    static func load() -> [Playlist] {
        var out: [Playlist] = []
        guard let raw = UserDefaults.standard.array(forKey: key) as? [[String: Any]] else {
            return []
        }
        for entry in raw {
            guard let idStr = entry["id"] as? String,
                  let uuid = UUID(uuidString: idStr),
                  let name = entry["name"] as? String,
                  let idsRaw = entry["trackIDs"] as? [String]
            else { continue }
            let ids = idsRaw.compactMap { UUID(uuidString: $0) }
            let source = entry["sourceFolder"] as? String
            out.append(Playlist(id: uuid, name: name, trackIDs: ids, sourceFolder: source))
        }
        return out
    }
}
