import Foundation

enum AssetLibraryActions {
    /// Route a media kind to its default subfolder under root, creating it if needed.
    static func bucketDirectory(for kind: MediaKind, root: URL) -> URL {
        let bucket: String
        switch kind {
        case .image: bucket = "images"
        case .video: bucket = "videos"
        case .audio: bucket = "audio"
        }
        let dir = root.appendingPathComponent(bucket, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copy urls into dir (best-effort, silent on individual failures). Returns success count.
    static func importByCopy(_ urls: [URL], to dir: URL) -> Int {
        let fm = FileManager.default
        var imported = 0
        for src in urls {
            let dest = FileDestinations.unique(for: src.lastPathComponent, in: dir)
            do {
                try fm.copyItem(at: src, to: dest)
                imported += 1
            } catch {}
        }
        return imported
    }

    /// Move or copy urls into dir — move when the file is already under root, copy otherwise.
    /// Skips non-media URLs and no-op moves (same directory). Throws on first FS error.
    static func moveOrImport(_ urls: [URL], to dir: URL, root: URL) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let destPath = dir.standardizedFileURL.path
        var changed = 0
        for src in urls {
            guard MediaKind.from(url: src) != nil else { continue }
            let srcDir = src.deletingLastPathComponent().standardizedFileURL.path
            guard srcDir != destPath else { continue }
            let dest = FileDestinations.unique(for: src.lastPathComponent, in: dir)
            if AssetURL.isUnder(src, root: root) {
                try fm.moveItem(at: src, to: dest)
            } else {
                try fm.copyItem(at: src, to: dest)
            }
            changed += 1
        }
        return changed
    }

    /// Create a folder named `name` under root, stripping / and : characters.
    /// Returns the created directory URL.
    static func createFolder(named name: String, under root: URL) throws -> URL {
        let safe = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let dir = root.appendingPathComponent(safe, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
