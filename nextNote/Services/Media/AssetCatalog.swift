import Foundation

// Flat-scan catalog for the dedicated Assets library root. Unlike the
// Media sidebar (which groups by first-level folder via MediaLibrary),
// this catalog is a single flat list of every indexable file under the
// root — the Asset Library view renders one grid with kind filters, so
// folder grouping would just add chrome.
//
// Indexes all MediaKind files (video / audio / image). The asset library
// is the one place images get surfaced as first-class items.
@MainActor
final class AssetCatalog: ObservableObject {

    struct Asset: Identifiable, Hashable {
        let id: URL
        var title: String
        var url: URL
        var kind: MediaKind
        var size: Int64?
        var modified: Date?
        /// First directory under the Assets root — e.g. `images`, `videos`,
        /// or a user-created folder. Empty string when the file is loose
        /// at the root.
        var folder: String
    }

    @Published private(set) var assets: [Asset] = []
    @Published private(set) var folders: [String] = []
    @Published private(set) var isScanning: Bool = false

    /// Scan `root` recursively and publish the resulting list + the set of
    /// first-level subfolders seen (used by the Asset Library sidebar).
    /// Runs the directory walk off the main actor to keep the UI
    /// responsive; files are sorted most-recently-modified first.
    func scan(root: URL?) async {
        isScanning = true
        defer { isScanning = false }

        guard let root else { assets = []; folders = []; return }

        let (foundAssets, foundFolders) = await Task.detached(priority: .userInitiated) {
            () -> ([Asset], [String]) in
            walkAssets(root: root)
        }.value

        assets = foundAssets.sorted {
            ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast)
        }
        folders = foundFolders.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Apply both filters in one pass. `folder == nil` → any folder.
    /// `kind == nil` → any kind. Empty-string folder means loose files
    /// at the root.
    func filtered(kind: MediaKind?, folder: String?) -> [Asset] {
        assets.filter { a in
            (kind == nil || a.kind == kind) &&
            (folder == nil || a.folder == folder)
        }
    }
}

private let assetSkipDirs: Set<String> = [".git", "node_modules", ".nextnote", ".Trash"]

private nonisolated func walkAssets(root: URL) -> ([AssetCatalog.Asset], [String]) {
    let fm = FileManager.default
    guard fm.fileExists(atPath: root.path) else { return ([], []) }

    // Snapshot first-level directories, so the Asset Library left pane
    // can list empty folders too (default "images"/"videos"/… are empty
    // on first launch but should still appear as targets).
    var topFolders = Set<String>()
    if let entries = try? fm.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) {
        for e in entries {
            let isDir = (try? e.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir && !assetSkipDirs.contains(e.lastPathComponent) {
                topFolders.insert(e.lastPathComponent)
            }
        }
    }

    guard let enumerator = fm.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
    ) else { return ([], Array(topFolders)) }

    let rootStd = root.standardizedFileURL.path
    var out: [AssetCatalog.Asset] = []
    for case let url as URL in enumerator {
        let name = url.lastPathComponent
        if assetSkipDirs.contains(name) {
            enumerator.skipDescendants()
            continue
        }
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
        ])
        if values?.isDirectory == true { continue }
        guard let kind = MediaKind.from(url: url) else { continue }

        // First directory component under root — empty for loose files
        // sitting at the root level.
        let full = url.standardizedFileURL.path
        var folder = ""
        if full.hasPrefix(rootStd) {
            var rel = String(full.dropFirst(rootStd.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            let segs = rel.split(separator: "/", omittingEmptySubsequences: true)
            if segs.count > 1 {
                folder = String(segs[0])
            }
        }

        out.append(.init(
            id: url,
            title: url.deletingPathExtension().lastPathComponent,
            url: url,
            kind: kind,
            size: values?.fileSize.map { Int64($0) },
            modified: values?.contentModificationDate,
            folder: folder
        ))
    }
    return (out, Array(topFolders))
}
