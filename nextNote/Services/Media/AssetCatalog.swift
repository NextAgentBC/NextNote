import Foundation

// Flat-scan catalog for the dedicated Assets library root. Unlike
// `MediaCatalog` (which is used by the Media sidebar and groups by
// first-level folder), this catalog is a single flat list of every
// indexable file under the root — the Asset Library view renders one
// grid with kind filters, so folder grouping would just add chrome.
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
    }

    @Published private(set) var assets: [Asset] = []
    @Published private(set) var isScanning: Bool = false

    /// Scan `root` recursively and publish the resulting list. Runs the
    /// directory walk off the main actor to keep the UI responsive; files
    /// are sorted by most-recently-modified so newly-dropped items show
    /// at the top.
    func scan(root: URL?) async {
        isScanning = true
        defer { isScanning = false }

        guard let root else { assets = []; return }

        let found = await Task.detached(priority: .userInitiated) { () -> [Asset] in
            walkAssets(root: root)
        }.value

        assets = found.sorted {
            ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast)
        }
    }

    func filtered(kind: MediaKind?) -> [Asset] {
        guard let kind else { return assets }
        return assets.filter { $0.kind == kind }
    }
}

private let assetSkipDirs: Set<String> = [".git", "node_modules", ".nextnote", ".Trash"]

private nonisolated func walkAssets(root: URL) -> [AssetCatalog.Asset] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: root.path) else { return [] }
    guard let enumerator = fm.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

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

        out.append(.init(
            id: url,
            title: url.deletingPathExtension().lastPathComponent,
            url: url,
            kind: kind,
            size: values?.fileSize.map { Int64($0) },
            modified: values?.contentModificationDate
        ))
    }
    return out
}
