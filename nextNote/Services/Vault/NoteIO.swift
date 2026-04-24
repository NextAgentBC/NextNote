import Foundation
import CryptoKit
#if os(macOS)
import AppKit
#endif

// Plain-text atomic read/write for vault .md files. UTF-8 only.
// Hash helper used everywhere we want to dedupe or invalidate caches.
enum NoteIO {
    enum IOError: LocalizedError {
        case invalidName(String)
        case alreadyExists(URL)
        case notFound(URL)

        var errorDescription: String? {
            switch self {
            case .invalidName(let name): return "Invalid name: \"\(name)\""
            case .alreadyExists(let url): return "Already exists: \(url.lastPathComponent)"
            case .notFound(let url): return "Not found: \(url.lastPathComponent)"
            }
        }
    }

    static func read(url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    static func write(url: URL, content: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Data(content.utf8)
        try data.write(to: url, options: [.atomic])
    }

    static func sha256(_ content: String) -> String {
        let digest = SHA256.hash(data: Data(content.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func fileModifiedAt(url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? Date()
    }

    // MARK: - Mutation

    /// Create a new .md file under `folderURL` with a unique, sanitized filename
    /// derived from `title`. On collision, appends " 2", " 3", ... until a free
    /// slot is found. Returns the URL actually written.
    static func createNote(inFolder folderURL: URL, title: String, initialContent: String = "") throws -> URL {
        let base = sanitize(title.isEmpty ? "Untitled" : title)
        guard !base.isEmpty else { throw IOError.invalidName(title) }
        let url = uniqueURL(inFolder: folderURL, baseName: base, ext: "md")
        try write(url: url, content: initialContent)
        return url
    }

    /// Create a subdirectory under `parentURL`. `name` is sanitized; on
    /// collision appends " 2", " 3", ....
    static func createFolder(inParent parentURL: URL, name: String) throws -> URL {
        let clean = sanitize(name)
        guard !clean.isEmpty else { throw IOError.invalidName(name) }
        let url = uniqueURL(inFolder: parentURL, baseName: clean, ext: nil)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Rename a file or folder in place. For files, preserves the original
    /// extension when `newName` has none. Errors if the target already exists.
    static func rename(_ url: URL, to newName: String) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { throw IOError.notFound(url) }

        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)

        let trimmed = sanitize(newName)
        guard !trimmed.isEmpty else { throw IOError.invalidName(newName) }

        let target: URL
        if isDir.boolValue {
            target = url.deletingLastPathComponent().appending(path: trimmed, directoryHint: .isDirectory)
        } else {
            let hasExt = (trimmed as NSString).pathExtension.isEmpty == false
            let finalName = hasExt ? trimmed : "\(trimmed).\(url.pathExtension)"
            target = url.deletingLastPathComponent().appending(path: finalName, directoryHint: .notDirectory)
        }
        if target == url { return url }
        if fm.fileExists(atPath: target.path) { throw IOError.alreadyExists(target) }
        try fm.moveItem(at: url, to: target)
        return target
    }

    /// Move to the system Trash so the user can recover. Returns the trashed
    /// URL (or nil if the platform doesn't surface one).
    @discardableResult
    static func delete(_ url: URL) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { throw IOError.notFound(url) }
        var resulting: NSURL?
        try fm.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    /// Move into `destFolderURL`. On collision, bumps basename with " 2", etc.
    static func move(_ url: URL, toFolder destFolderURL: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { throw IOError.notFound(url) }

        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)

        let base: String
        let ext: String?
        if isDir.boolValue {
            base = url.lastPathComponent
            ext = nil
        } else {
            base = url.deletingPathExtension().lastPathComponent
            ext = url.pathExtension
        }
        let target = uniqueURL(inFolder: destFolderURL, baseName: base, ext: ext)
        try fm.createDirectory(at: destFolderURL, withIntermediateDirectories: true)
        try fm.moveItem(at: url, to: target)
        return target
    }

    /// Copy an external file (or folder) into `destFolderURL`. Preserves
    /// basename + extension; bumps " 2", " 3", ... on collision. Creates the
    /// destination folder if missing.
    static func copyInto(folder destFolderURL: URL, source: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw IOError.notFound(source) }

        var isDir: ObjCBool = false
        fm.fileExists(atPath: source.path, isDirectory: &isDir)

        let base: String
        let ext: String?
        if isDir.boolValue {
            base = source.lastPathComponent
            ext = nil
        } else {
            base = source.deletingPathExtension().lastPathComponent
            ext = source.pathExtension.isEmpty ? nil : source.pathExtension
        }

        try fm.createDirectory(at: destFolderURL, withIntermediateDirectories: true)
        let target = uniqueURL(inFolder: destFolderURL, baseName: base, ext: ext)
        try fm.copyItem(at: source, to: target)
        return target
    }

    /// Duplicate a file in place: "notes.md" → "notes 2.md".
    static func duplicate(_ url: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { throw IOError.notFound(url) }
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        let parent = url.deletingLastPathComponent()
        let base: String
        let ext: String?
        if isDir.boolValue {
            base = url.lastPathComponent
            ext = nil
        } else {
            base = url.deletingPathExtension().lastPathComponent
            ext = url.pathExtension
        }
        let target = uniqueURL(inFolder: parent, baseName: base, ext: ext)
        try fm.copyItem(at: url, to: target)
        return target
    }

    // MARK: - Helpers

    /// Strip path separators and trim whitespace. Does NOT strip extensions —
    /// callers decide whether to keep/add one.
    static func sanitize(_ raw: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:\0")
        let cleaned = raw.components(separatedBy: bad).joined()
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Return a URL for "baseName[.ext]" under `folder` that doesn't collide.
    /// Appends " 2", " 3", ... as needed.
    private static func uniqueURL(inFolder folder: URL, baseName: String, ext: String?) -> URL {
        let fm = FileManager.default
        var attempt = 1
        while true {
            let name = attempt == 1 ? baseName : "\(baseName) \(attempt)"
            let full = (ext?.isEmpty == false) ? "\(name).\(ext!)" : name
            let url = folder.appending(path: full, directoryHint: ext == nil ? .isDirectory : .notDirectory)
            if !fm.fileExists(atPath: url.path) { return url }
            attempt += 1
        }
    }
}
