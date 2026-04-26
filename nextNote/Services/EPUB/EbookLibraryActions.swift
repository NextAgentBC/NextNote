import Foundation
import SwiftData

/// File-system + SwiftData operations for the Ebooks library: create /
/// rename / delete subfolders under the Ebooks root, and move a Book
/// (its on-disk .epub / .pdf file) between folders. Keeps Book.relativePath
/// in sync with the file's actual location so reader and Reveal-in-Finder
/// keep working after a move.
@MainActor
enum EbookLibraryActions {

    enum ActionError: LocalizedError {
        case noRoot
        case invalidName
        case folderExists(String)
        case folderNotEmpty(String)
        case fs(String)

        var errorDescription: String? {
            switch self {
            case .noRoot: return "Ebooks folder is not configured."
            case .invalidName: return "Folder name can't be empty or contain path separators."
            case .folderExists(let n): return "A folder named \"\(n)\" already exists."
            case .folderNotEmpty(let n): return "Folder \"\(n)\" still has files. Move or delete them first."
            case .fs(let m): return m
            }
        }
    }

    /// Sanitize a folder name for the filesystem: drop path separators
    /// and reserved characters. Returns nil for empty / pathological
    /// input.
    static func sanitize(_ raw: String) -> String? {
        let bad: Set<Character> = ["/", ":", "\\", "*", "?", "\"", "<", ">", "|", "\0"]
        var out = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !bad.contains($0) }
        while out.hasPrefix(".") { out.removeFirst() }
        if out.isEmpty { return nil }
        if out.count > 80 { out = String(out.prefix(80)) }
        return out
    }

    @discardableResult
    static func createFolder(named raw: String, under root: URL) throws -> URL {
        guard let name = sanitize(raw) else { throw ActionError.invalidName }
        let dir = root.appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: dir.path) {
            throw ActionError.folderExists(name)
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        } catch {
            throw ActionError.fs("Create folder failed: \(error.localizedDescription)")
        }
        return dir
    }

    /// Rename a first-level subfolder. Books inside get their
    /// `relativePath` updated to reflect the new directory.
    static func renameFolder(
        from oldName: String,
        to newName: String,
        under root: URL,
        books: [Book],
        vault: VaultStore,
        modelContext: ModelContext
    ) throws {
        guard let clean = sanitize(newName) else { throw ActionError.invalidName }
        let oldURL = root.appendingPathComponent(oldName, isDirectory: true)
        let newURL = root.appendingPathComponent(clean, isDirectory: true)
        if FileManager.default.fileExists(atPath: newURL.path) {
            throw ActionError.folderExists(clean)
        }
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            throw ActionError.fs("Rename failed: \(error.localizedDescription)")
        }

        // Patch every Book whose on-disk path now lives under the new
        // folder. We re-resolve via the vault rather than guessing
        // string-relative paths.
        let oldPrefixURL = oldURL.standardizedFileURL.path + "/"
        let newPrefixURL = newURL.standardizedFileURL.path + "/"
        for book in books {
            guard let url = EPUBImporter.resolveFileURL(book.relativePath, vault: vault) else { continue }
            let p = url.standardizedFileURL.path
            if p.hasPrefix(oldPrefixURL) {
                let movedPath = newPrefixURL + String(p.dropFirst(oldPrefixURL.count))
                let movedURL = URL(fileURLWithPath: movedPath)
                book.relativePath = vault.relativePath(for: movedURL) ?? movedURL.lastPathComponent
            }
        }
        try? modelContext.save()
    }

    /// Delete an empty subfolder. Refuses if any file is inside; user
    /// has to move books out first to avoid surprise data loss.
    static func deleteFolder(named name: String, under root: URL) throws {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        let children = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        if !children.isEmpty {
            throw ActionError.folderNotEmpty(name)
        }
        do {
            try FileManager.default.removeItem(at: dir)
        } catch {
            throw ActionError.fs("Delete failed: \(error.localizedDescription)")
        }
    }

    /// Move a book's on-disk file into the named subfolder ("" = root).
    /// Updates the Book's `relativePath` so the reader keeps working.
    static func moveBook(
        _ book: Book,
        toFolder folder: String,
        root: URL,
        vault: VaultStore,
        modelContext: ModelContext
    ) throws {
        let cleanFolder = folder.isEmpty ? "" : (sanitize(folder) ?? folder)
        let dir = cleanFolder.isEmpty ? root : root.appendingPathComponent(cleanFolder, isDirectory: true)
        if !cleanFolder.isEmpty {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        guard let oldURL = EPUBImporter.resolveFileURL(book.relativePath, vault: vault) else {
            throw ActionError.fs("Couldn't locate the book file on disk.")
        }

        let dest = dir.appendingPathComponent(oldURL.lastPathComponent)
        if dest.standardizedFileURL.path == oldURL.standardizedFileURL.path { return }

        let fm = FileManager.default
        let destExists = fm.fileExists(atPath: dest.path)
        let oldExists = fm.fileExists(atPath: oldURL.path)

        if destExists && !oldExists {
            // File already moved out-of-band (Finder drag, previous run
            // crashed mid-move, or stale Book.relativePath). Just sync
            // the model — no FS work needed.
            book.relativePath = vault.relativePath(for: dest) ?? dest.lastPathComponent
            try? modelContext.save()
            return
        }
        if destExists && oldExists {
            throw ActionError.fs("A file with the same name already exists in \"\(cleanFolder.isEmpty ? "Ebooks root" : cleanFolder)\".")
        }
        guard oldExists else {
            // Neither location has the file — Book entry is orphaned. Bail
            // without touching anything; let the user re-import or remove
            // the book record.
            throw ActionError.fs("Couldn't find the book file on disk. It may have been moved or deleted in Finder.")
        }
        do {
            try fm.moveItem(at: oldURL, to: dest)
        } catch {
            throw ActionError.fs("Move failed: \(error.localizedDescription)")
        }

        book.relativePath = vault.relativePath(for: dest) ?? dest.lastPathComponent
        try? modelContext.save()
    }

    /// First-level subfolders under the Ebooks root, even when empty.
    /// Sorted case-insensitive so the sidebar order matches Finder.
    static func discoverFolders(under root: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [String] = []
        for url in entries {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { out.append(url.lastPathComponent) }
        }
        return out.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

}
