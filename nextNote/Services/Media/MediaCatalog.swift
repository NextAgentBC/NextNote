import Foundation

// Transient, in-memory music + video catalog aggregated from the main vault
// and user-added media roots. Not SwiftData-backed — the list is re-derived
// on each scan. Separate from the heavier `MediaLibrary` ambient service.
@MainActor
final class MediaCatalog: ObservableObject {

    struct MediaFile: Identifiable, Hashable {
        let id: URL
        var title: String
        var url: URL
        var kind: MediaKind
        /// Label the sidebar groups under — the closest directory name
        /// between `mediaRoot` and the file. Files dropped directly at the
        /// root get "" (rendered under an "Uncategorized" heading).
        var folder: String
    }

    /// A single collapsible group in the sidebar — one per parent folder.
    struct MediaGroup: Identifiable, Hashable {
        var id: String { folder }
        var folder: String
        var items: [MediaFile]
    }

    @Published private(set) var music: [MediaFile] = []
    @Published private(set) var videos: [MediaFile] = []
    @Published private(set) var isScanning: Bool = false

    /// Music files grouped by their first-level folder under `mediaRoot`.
    var musicGroups: [MediaGroup] { Self.group(music) }
    var videoGroups: [MediaGroup] { Self.group(videos) }

    func scan(mediaRoot: URL?) async {
        isScanning = true
        defer { isScanning = false }

        guard let root = mediaRoot else {
            music = []
            videos = []
            return
        }

        let rootStd = root.standardizedFileURL.path
        var musicBucket: [MediaFile] = []
        var videoBucket: [MediaFile] = []

        let files = await Task.detached(priority: .userInitiated) { () -> [(URL, MediaKind)] in
            walk(root: root)
        }.value
        for (url, kind) in files {
            let title = url.deletingPathExtension().lastPathComponent
            let folder = Self.firstLevelFolder(of: url, under: rootStd)
            let entry = MediaFile(id: url, title: title, url: url, kind: kind, folder: folder)
            switch kind {
            case .audio: musicBucket.append(entry)
            case .video: videoBucket.append(entry)
            case .image: continue  // images belong to the Asset Library, not the Media sidebar
            }
        }

        music = dedupe(musicBucket).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        videos = dedupe(videoBucket).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Return the first directory component under `rootPath` — e.g. a file at
    /// `<root>/邓紫棋/song.mp3` becomes `"邓紫棋"`; nested paths collapse to
    /// their topmost folder under the root so the sidebar stays two levels
    /// deep max (folder header → track).
    private static func firstLevelFolder(of file: URL, under rootPath: String) -> String {
        let full = file.standardizedFileURL.path
        guard full.hasPrefix(rootPath) else { return "" }
        var rel = String(full.dropFirst(rootPath.count))
        if rel.hasPrefix("/") { rel.removeFirst() }
        let segments = rel.split(separator: "/", omittingEmptySubsequences: true)
        if segments.count <= 1 { return "" }   // file sits directly at root
        return String(segments[0])
    }

    private static func group(_ files: [MediaFile]) -> [MediaGroup] {
        var bucket: [String: [MediaFile]] = [:]
        for f in files { bucket[f.folder, default: []].append(f) }
        let ordered = bucket.keys.sorted { a, b in
            // Unsorted loose files last.
            if a.isEmpty { return false }
            if b.isEmpty { return true }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        return ordered.map { MediaGroup(folder: $0, items: bucket[$0] ?? []) }
    }

    private func dedupe(_ items: [MediaFile]) -> [MediaFile] {
        var seen = Set<URL>()
        var out: [MediaFile] = []
        for item in items where seen.insert(item.url).inserted {
            out.append(item)
        }
        return out
    }
}

private let skippedDirs: Set<String> = [".git", "node_modules", ".nextnote", ".Trash"]
private nonisolated func walk(root: URL) -> [(URL, MediaKind)] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: root.path) else { return [] }
    guard let enumerator = fm.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

    var out: [(URL, MediaKind)] = []
    for case let url as URL in enumerator {
        let name = url.lastPathComponent
        if skippedDirs.contains(name) {
            enumerator.skipDescendants()
            continue
        }
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard !isDir else { continue }
        if let kind = MediaKind.from(url: url) {
            out.append((url, kind))
        }
    }
    return out
}
