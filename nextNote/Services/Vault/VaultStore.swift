import Foundation
import AppKit
import SwiftUI

@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var root: URL?
    @Published private(set) var tree: FolderNode = .empty
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var lastError: String?

    private var accessing: URL?

    /// Expose scanner constants for sidebar display.
    static let imageExts: Set<String> = VaultTreeScanner.imageExts

    init() {
        // Ownership of the notes-root bookmark has moved to LibraryRoots.
        // Don't resolve here — ContentView calls `adopt(url:)` after
        // LibraryRoots resolves its Notes bookmark.
    }

    /// Hand over the Notes root resolved by LibraryRoots. No bookmark is saved.
    func adoptNotesRoot(_ url: URL?) {
        guard let url else {
            accessing?.stopAccessingSecurityScopedResource()
            accessing = nil
            root = nil
            tree = .empty
            return
        }
        if root == url { return }
        adopt(url: url, persistBookmark: false)
    }

    deinit {
        accessing?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Root selection

    func pickVault() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Vault"
        panel.message = "Pick a folder to use as your nextNote vault. Notes will live here as .md files."

        let response = await panel.beginSheet()
        guard response == .OK, let url = panel.url else { return }
        adopt(url: url, persistBookmark: true)
    }

    private func restoreIfAvailable() {
        do {
            guard let url = try VaultBookmark.resolve() else { return }
            adopt(url: url, persistBookmark: false)
        } catch {
            lastError = "Vault bookmark is stale: \(error.localizedDescription). Pick the folder again."
            VaultBookmark.clear()
        }
    }

    private func adopt(url: URL, persistBookmark: Bool) {
        accessing?.stopAccessingSecurityScopedResource()
        accessing = nil
        guard url.startAccessingSecurityScopedResource() else {
            lastError = "Could not access \(url.path). Sandbox denied."
            return
        }
        accessing = url
        root = url
        lastError = nil
        if persistBookmark {
            try? VaultBookmark.save(url)
        }
        Task { await scan() }
    }

    // MARK: - Scan

    func scan() async {
        guard let root else { return }
        isScanning = true
        defer { isScanning = false }
        let (built, truncated) = VaultTreeScanner.buildTree(root: root)
        if truncated {
            lastError = "Vault has >\(VaultTreeScanner.maxNodes) items. Tree truncated for performance."
        }
        tree = built
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

    // MARK: - Forget

    func forgetVault() {
        accessing?.stopAccessingSecurityScopedResource()
        accessing = nil
        root = nil
        tree = .empty
        VaultBookmark.clear()
    }
}

private extension NSOpenPanel {
    func beginSheet() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            self.begin { response in
                continuation.resume(returning: response)
            }
        }
    }
}
