import Foundation

enum AssetURL {
    /// True iff `url` lives strictly under `root` (not equal, not outside).
    static func isUnder(_ url: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(rootPath + "/")
    }
}
