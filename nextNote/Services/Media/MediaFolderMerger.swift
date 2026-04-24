import Foundation

// Merge one media sub-folder into another. Used by sidebar drag-and-drop —
// dragging "GEM 邓紫棋" onto "邓紫棋" moves every file from source → target,
// handles name collisions with " (N)" suffix, then removes the (now empty)
// source directory so there's one folder per artist.
@MainActor
enum MediaFolderMerger {

    enum MergeError: LocalizedError {
        case sameFolder
        case notADirectory(URL)
        case moveFailed(String)

        var errorDescription: String? {
            switch self {
            case .sameFolder:          return "Source and target are the same folder."
            case .notADirectory(let u): return "\(u.lastPathComponent) is not a folder."
            case .moveFailed(let m):   return "Move failed: \(m)"
            }
        }
    }

    struct Result {
        var movedCount: Int
        var skippedCount: Int
        var sourceRemoved: Bool
    }

    /// Move the immediate contents of `source` into `target`. Recursively
    /// enters subdirectories so nested structure is preserved. If `source`
    /// ends up empty, it is removed.
    @discardableResult
    static func merge(source: URL, into target: URL) throws -> Result {
        let fm = FileManager.default
        let src = source.standardizedFileURL
        let tgt = target.standardizedFileURL
        guard src.path != tgt.path else { throw MergeError.sameFolder }
        guard isDirectory(src) else { throw MergeError.notADirectory(src) }
        guard isDirectory(tgt) else {
            // Auto-create if missing (merge onto a header for a new folder).
            try fm.createDirectory(at: tgt, withIntermediateDirectories: true)
            return try merge(source: src, into: tgt)
        }

        var moved = 0
        var skipped = 0
        do {
            let entries = try fm.contentsOfDirectory(
                at: src,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for entry in entries {
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir {
                    // Recurse: merge the sub-dir's contents into the target
                    // so nested layouts collapse one level. User's drag is
                    // "merge A into B" — sub-dirs under A flatten under B
                    // unless they collide with existing sub-dirs in B, in
                    // which case we recurse into the collision.
                    let nestedTarget = tgt.appendingPathComponent(entry.lastPathComponent, isDirectory: true)
                    let sub = try merge(source: entry, into: nestedTarget)
                    moved += sub.movedCount
                    skipped += sub.skippedCount
                } else {
                    let dest = uniqueDestination(for: entry.lastPathComponent, in: tgt)
                    do {
                        try fm.moveItem(at: entry, to: dest)
                        moved += 1
                    } catch {
                        skipped += 1
                    }
                }
            }
        } catch {
            throw MergeError.moveFailed(error.localizedDescription)
        }

        // Remove source if empty.
        var removed = false
        if let remaining = try? fm.contentsOfDirectory(atPath: src.path),
           remaining.allSatisfy({ $0.hasPrefix(".") }) {
            try? fm.removeItem(at: src)
            removed = true
        }

        return Result(movedCount: moved, skippedCount: skipped, sourceRemoved: removed)
    }

    // MARK: - Helpers

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        return isDir.boolValue
    }

    private static func uniqueDestination(for filename: String, in dir: URL) -> URL {
        let fm = FileManager.default
        var dest = dir.appendingPathComponent(filename)
        if !fm.fileExists(atPath: dest.path) { return dest }
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            dest = dir.appendingPathComponent(candidate)
            if !fm.fileExists(atPath: dest.path) { return dest }
            n += 1
        }
    }
}
