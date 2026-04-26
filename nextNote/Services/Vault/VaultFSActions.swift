import Foundation

enum VaultFSActions {
    // MARK: - Path helpers

    static func relativePath(for url: URL, root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        guard full.hasPrefix(rootPath) else { return nil }
        let rel = String(full.dropFirst(rootPath.count))
        return rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
    }

    static func folderURL(for relativePath: String, root: URL) -> URL {
        if relativePath.isEmpty { return root }
        return root.appending(path: relativePath, directoryHint: .isDirectory)
    }

    // MARK: - Mutations

    static func createNote(inFolder parentPath: String, root: URL, title: String, initialContent: String = "") throws -> String {
        let parent = folderURL(for: parentPath, root: root)
        let url = try NoteIO.createNote(inFolder: parent, title: title, initialContent: initialContent)
        return relativePath(for: url, root: root) ?? url.lastPathComponent
    }

    static func createFolder(inParent parentPath: String, root: URL, name: String) throws -> String {
        let parent = folderURL(for: parentPath, root: root)
        let url = try NoteIO.createFolder(inParent: parent, name: name)
        return relativePath(for: url, root: root) ?? url.lastPathComponent
    }

    static func rename(_ relPath: String, to newName: String, root: URL) throws -> String {
        let url = root.appending(path: relPath, directoryHint: .notDirectory)
        let wasDirectory = isDirectory(url)
        let newURL = try NoteIO.rename(url, to: newName)
        let newRel = relativePath(for: newURL, root: root) ?? newURL.lastPathComponent
        if wasDirectory {
            ChatStore.renameDirectory(from: relPath, to: newRel, vaultRoot: root)
        } else {
            ChatStore.rename(from: relPath, to: newRel, vaultRoot: root)
        }
        return newRel
    }

    static func delete(_ relPath: String, root: URL) throws {
        let url = root.appending(path: relPath, directoryHint: .notDirectory)
        let wasDirectory = isDirectory(url)
        _ = try NoteIO.delete(url)
        if wasDirectory {
            ChatStore.deleteDirectory(prefix: relPath, vaultRoot: root)
        } else {
            ChatStore.delete(relativePath: relPath, vaultRoot: root)
        }
    }

    static func move(_ relPath: String, toFolder destPath: String, root: URL) throws -> String {
        let source = root.appending(path: relPath, directoryHint: .notDirectory)
        let dest = folderURL(for: destPath, root: root)
        let wasDirectory = isDirectory(source)
        let newURL = try NoteIO.move(source, toFolder: dest)
        let newRel = relativePath(for: newURL, root: root) ?? newURL.lastPathComponent
        if wasDirectory {
            ChatStore.renameDirectory(from: relPath, to: newRel, vaultRoot: root)
        } else {
            ChatStore.rename(from: relPath, to: newRel, vaultRoot: root)
        }
        return newRel
    }

    /// Returns imported relative paths. Per-file errors are passed back via `onError`.
    static func importFiles(_ sources: [URL], intoFolder parentPath: String, root: URL, onError: (String) -> Void) -> [String] {
        let dest = folderURL(for: parentPath, root: root)
        var imported: [String] = []
        for src in sources {
            let accessing = src.startAccessingSecurityScopedResource()
            defer { if accessing { src.stopAccessingSecurityScopedResource() } }
            do {
                let newURL = try NoteIO.copyInto(folder: dest, source: src)
                imported.append(relativePath(for: newURL, root: root) ?? newURL.lastPathComponent)
            } catch {
                onError("Import failed for \(src.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return imported
    }

    static func duplicate(_ relPath: String, root: URL) throws -> String {
        let url = root.appending(path: relPath, directoryHint: .notDirectory)
        let newURL = try NoteIO.duplicate(url)
        return relativePath(for: newURL, root: root) ?? newURL.lastPathComponent
    }

    // MARK: - Internal

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }
}
