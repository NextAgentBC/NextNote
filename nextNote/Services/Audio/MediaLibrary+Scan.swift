import Foundation

extension MediaLibrary {
    /// Scan an arbitrary root (the vault's Media library root). Drops
    /// tracks that live *under* this root and no longer exist, leaves
    /// tracks from other roots alone, and ingests any new files it finds.
    /// This is the single entry point the sidebar + ContentView use —
    /// keeps the sidebar tree and the Media Library popup reading from
    /// the same `@Published tracks` list, so a rename / remove / add in
    /// one UI is live-visible in the other.
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

        let found = MediaScanner.walkForMedia(root: root)
        _ = addFiles(found)
    }

    /// Tracks of `kind` grouped by their first-level folder under `root`.
    /// Sorted alphabetically with "loose" files last. The sidebar + popup
    /// share this derivation, so they stay in sync automatically.
    func groups(kind: MediaKind, under root: URL?) -> [MediaGroup] {
        let rootPath = root?.standardizedFileURL.path
        let filtered = tracks.filter { MediaKind.from(url: $0.url) == kind }
        var bucket: [String: [Track]] = [:]
        for t in filtered {
            let folder = MediaScanner.firstLevelFolder(of: t.url, under: rootPath)
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
}
