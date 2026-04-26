import Foundation

/// Pure file-system helpers for the media library. No state, no
/// `@Published` — extracted so MediaLibrary itself can stay focused on
/// the observable store.
enum MediaScanner {
    /// Walk `root` recursively, returning every file whose extension
    /// `MediaKind.from(url:)` recognizes. Synchronous: FileManager's
    /// NSEnumerator iterator is @preconcurrency-banned in async contexts
    /// under Swift 6 strict mode.
    nonisolated static func walkForMedia(root: URL) -> [URL] {
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

    /// First-level subfolder name relative to a root. Used to group
    /// tracks by artist/category folder. `<root>/邓紫棋/song.mp3` →
    /// `"邓紫棋"`. Files directly at the root (or outside it) → `""` so
    /// callers can render them under an "Uncategorized" heading.
    static func firstLevelFolder(of file: URL, under rootPath: String?) -> String {
        guard let rootPath else { return "" }
        let full = file.standardizedFileURL.path
        guard full.hasPrefix(rootPath) else { return "" }
        var rel = String(full.dropFirst(rootPath.count))
        if rel.hasPrefix("/") { rel.removeFirst() }
        let segments = rel.split(separator: "/", omittingEmptySubsequences: true)
        if segments.count <= 1 { return "" }
        return String(segments[0])
    }
}
