import Foundation
import AppKit
import SwiftUI

@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var root: URL?
    @Published private(set) var tree: FolderNode = .empty
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var lastError: String?

    /// Expose scanner constants for sidebar display.
    static let imageExts: Set<String> = VaultTreeScanner.imageExts

    /// Adopt the project root resolved by ProjectStore. ProjectStore owns
    /// the security-scoped bookmark + access lifetime; this just tracks
    /// the URL and rescans the tree.
    func adoptRoot(_ url: URL?) {
        guard let url else {
            root = nil
            tree = .empty
            return
        }
        if root == url { return }
        root = url
        lastError = nil
        Task { await scan() }
    }

    // MARK: - Scan

    func scan() async {
        guard let root else { return }
        if isScanning { return }
        isScanning = true
        defer { isScanning = false }
        let result = await Task.detached(priority: .userInitiated) {
            VaultTreeScanner.buildTree(root: root)
        }.value
        if result.truncated {
            lastError = "Vault has >\(VaultTreeScanner.maxNodes) items. Tree truncated for performance."
        }
        tree = result.tree
    }

    func rescan(subpath: String) async {
        await scan()
    }

    // MARK: - Path resolution

    func url(for relativePath: String) -> URL? {
        guard let root else { return nil }
        if relativePath.isEmpty { return root }
        return root.appending(path: relativePath, directoryHint: .notDirectory)
    }

    func relativePath(for url: URL) -> String? {
        guard let root else { return nil }
        return VaultFSActions.relativePath(for: url, root: root)
    }

    // MARK: - Mutations

    @discardableResult
    func createNote(inFolder parentRelativePath: String, title: String, initialContent: String = "") async throws -> String {
        guard let root else { throw NoteIO.IOError.notFound(URL(fileURLWithPath: "/")) }
        let relPath = try VaultFSActions.createNote(inFolder: parentRelativePath, root: root, title: title, initialContent: initialContent)
        await scan()
        return relPath
    }

    /// Create a new, empty `.nndraw` drawing note under `parentRelativePath`.
    /// Seeds the file with an empty `DrawingDoc` JSON and returns its
    /// vault-relative path. Rescans so the sidebar shows it immediately.
    @discardableResult
    func createDrawing(inFolder parentRelativePath: String, title: String = "Drawing") async throws -> String {
        guard let root else { throw NoteIO.IOError.notFound(URL(fileURLWithPath: "/")) }
        let parentURL = parentRelativePath.isEmpty
            ? root
            : root.appending(path: parentRelativePath, directoryHint: .isDirectory)
        let seed = (try? DrawingIO.encodeString(DrawingDoc())) ?? "{}"
        let url = try NoteIO.createFile(inFolder: parentURL, title: title, ext: "nndraw", initialContent: seed)
        await scan()
        return VaultFSActions.relativePath(for: url, root: root) ?? url.lastPathComponent
    }

    @discardableResult
    func createFolder(inParent parentRelativePath: String, name: String) async throws -> String {
        guard let root else { throw NoteIO.IOError.notFound(URL(fileURLWithPath: "/")) }
        let relPath = try VaultFSActions.createFolder(inParent: parentRelativePath, root: root, name: name)
        await scan()
        return relPath
    }

    @discardableResult
    func rename(_ relPath: String, to newName: String) async throws -> String {
        guard let root else { throw NoteIO.IOError.notFound(URL(fileURLWithPath: "/")) }
        let newRel = try VaultFSActions.rename(relPath, to: newName, root: root)
        await scan()
        return newRel
    }

    func delete(_ relPath: String) async throws {
        guard let root else { throw NoteIO.IOError.notFound(URL(fileURLWithPath: "/")) }
        try VaultFSActions.delete(relPath, root: root)
        await scan()
    }

    @discardableResult
    func move(_ relPath: String, toFolder destFolderRelativePath: String) async throws -> String {
        guard let root else { throw NoteIO.IOError.notFound(URL(fileURLWithPath: "/")) }
        let newRel = try VaultFSActions.move(relPath, toFolder: destFolderRelativePath, root: root)
        await scan()
        return newRel
    }

    @discardableResult
    func importFiles(_ sources: [URL], intoFolder parentRelativePath: String) async throws -> [String] {
        guard let root else { throw NoteIO.IOError.notFound(URL(fileURLWithPath: "/")) }
        let imported = VaultFSActions.importFiles(sources, intoFolder: parentRelativePath, root: root) { [weak self] err in
            self?.lastError = err
        }
        await scan()
        return imported
    }

    @discardableResult
    func duplicate(_ relPath: String) async throws -> String {
        guard let root else { throw NoteIO.IOError.notFound(URL(fileURLWithPath: "/")) }
        let newRel = try VaultFSActions.duplicate(relPath, root: root)
        await scan()
        return newRel
    }
}
