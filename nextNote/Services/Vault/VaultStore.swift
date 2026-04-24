import Foundation
import AppKit
import SwiftUI

// Holds the user's vault root URL, keeps a security-scoped access open for
// the app session, and publishes a FolderNode tree derived from disk.
//
// Scan scope: .md files + directories. Skips hidden files, .git, node_modules,
// and bails early at a hard node cap so a giant directory can't lock the UI.
@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var root: URL?
    @Published private(set) var tree: FolderNode = .empty
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var lastError: String?

    private var accessing: URL?

    private static let maxNodes = 10_000
    private static let skippedDirs: Set<String> = [".git", "node_modules", ".nextnote"]
    /// Image file extensions that show up in the sidebar tree alongside
    /// .md and playable media. Images don't get a dedicated tab view yet —
    /// they're there so drag-drop → paste-as-embed workflow works.
    static let imageExts: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff", "svg"
    ]

    init() {
        VaultStoreAccess.bind(self)
        // Ownership of the notes-root bookmark has moved to LibraryRoots.
        // Don't resolve here — ContentView calls `adopt(url:)` after
        // LibraryRoots resolves its Notes bookmark.
    }

    /// Public entry for ContentView to hand over the Notes root URL
    /// resolved by `LibraryRoots`. No own bookmark is saved; LibraryRoots
    /// is the single source of truth.
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

    /// Show NSOpenPanel, persist bookmark, start scan.
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

    /// Resolve a previously-persisted bookmark on launch.
    private func restoreIfAvailable() {
        do {
            guard let url = try VaultBookmark.resolve() else { return }
            adopt(url: url, persistBookmark: false)
        } catch {
            lastError = "Vault bookmark is stale: \(error.localizedDescription). Pick the folder again."
            VaultBookmark.clear()
        }
    }

    /// Release the old root, open the new one, persist bookmark, kick scan.
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
        AITextService.shared.bindVault(rootURL: url)
        Task { await scan() }
    }

    // MARK: - Scan

    /// Rebuild the full tree from disk. Cheap enough to run on each rescan
    /// for vaults under ~10k nodes. Beyond that it bails with a warning.
    func scan() async {
        guard let root else { return }
        isScanning = true
        defer { isScanning = false }

        var nodeCount = 0
        let built = Self.scanDirectory(
            at: root,
            relativePath: "",
            nodeCount: &nodeCount
        )
        if nodeCount >= Self.maxNodes {
            lastError = "Vault has >\(Self.maxNodes) items. Tree truncated for performance."
        }
        tree = built
    }

    /// Re-scan one subpath. For R1 we just redo the whole tree — simple, and
    /// correctness beats speed at this stage. Revisit if vaults get big.
    func rescan(subpath: String) async {
        await scan()
    }

    // MARK: - Path resolution

    /// Turn a vault-relative path ("projects/a.md") into a full URL under the root.
    func url(for relativePath: String) -> URL? {
        guard let root else { return nil }
        if relativePath.isEmpty { return root }
        return root.appending(path: relativePath, directoryHint: .notDirectory)
    }

    /// Inverse of `url(for:)`. Returns the vault-relative path for `url`, or
    /// nil if `url` isn't inside the vault root.
    func relativePath(for url: URL) -> String? {
        guard let root else { return nil }
        let rootPath = root.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        guard full.hasPrefix(rootPath) else { return nil }
        let rel = String(full.dropFirst(rootPath.count))
        return rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
    }

    // MARK: - Mutation
    //
    // All mutations: resolve folder/file URL, hand off to NoteIO, refresh the
    // tree, return the new vault-relative path. Views call these from a
    // button/menu handler and then ask AppState to sync any open tabs.

    /// `parentRelativePath` = "" creates at vault root.
    @discardableResult
    func createNote(inFolder parentRelativePath: String, title: String, initialContent: String = "") async throws -> String {
        guard let parent = folderURL(for: parentRelativePath) else {
            throw NoteIO.IOError.notFound(root ?? URL(fileURLWithPath: "/"))
        }
        let url = try NoteIO.createNote(inFolder: parent, title: title, initialContent: initialContent)
        await scan()
        return relativePath(for: url) ?? url.lastPathComponent
    }

    @discardableResult
    func createFolder(inParent parentRelativePath: String, name: String) async throws -> String {
        guard let parent = folderURL(for: parentRelativePath) else {
            throw NoteIO.IOError.notFound(root ?? URL(fileURLWithPath: "/"))
        }
        let url = try NoteIO.createFolder(inParent: parent, name: name)
        await scan()
        return relativePath(for: url) ?? url.lastPathComponent
    }

    @discardableResult
    func rename(_ relPath: String, to newName: String) async throws -> String {
        guard let url = self.url(for: relPath), let root else {
            throw NoteIO.IOError.notFound(root ?? URL(fileURLWithPath: "/"))
        }
        let wasDirectory: Bool = {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }()
        let newURL = try NoteIO.rename(url, to: newName)
        let newRel = relativePath(for: newURL) ?? newURL.lastPathComponent
        if wasDirectory {
            ChatStore.renameDirectory(from: relPath, to: newRel, vaultRoot: root)
        } else {
            ChatStore.rename(from: relPath, to: newRel, vaultRoot: root)
        }
        await scan()
        return newRel
    }

    func delete(_ relPath: String) async throws {
        guard let url = self.url(for: relPath), let root else {
            throw NoteIO.IOError.notFound(root ?? URL(fileURLWithPath: "/"))
        }
        let wasDirectory: Bool = {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }()
        _ = try NoteIO.delete(url)
        if wasDirectory {
            ChatStore.deleteDirectory(prefix: relPath, vaultRoot: root)
        } else {
            ChatStore.delete(relativePath: relPath, vaultRoot: root)
        }
        await scan()
    }

    @discardableResult
    func move(_ relPath: String, toFolder destFolderRelativePath: String) async throws -> String {
        guard let source = self.url(for: relPath),
              let dest = folderURL(for: destFolderRelativePath),
              let root else {
            throw NoteIO.IOError.notFound(root ?? URL(fileURLWithPath: "/"))
        }
        let wasDirectory: Bool = {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: source.path, isDirectory: &isDir)
            return isDir.boolValue
        }()
        let newURL = try NoteIO.move(source, toFolder: dest)
        let newRel = relativePath(for: newURL) ?? newURL.lastPathComponent
        if wasDirectory {
            ChatStore.renameDirectory(from: relPath, to: newRel, vaultRoot: root)
        } else {
            ChatStore.rename(from: relPath, to: newRel, vaultRoot: root)
        }
        await scan()
        return newRel
    }

    /// Import one or more external files (usually from Finder drag-drop) into
    /// `parentRelativePath`. Each source is copied; names collide via " 2",
    /// " 3", etc. Security-scoped access is opened per source URL so Finder
    /// drops into a sandboxed app work.
    @discardableResult
    func importFiles(_ sources: [URL], intoFolder parentRelativePath: String) async throws -> [String] {
        guard let dest = folderURL(for: parentRelativePath) else {
            throw NoteIO.IOError.notFound(root ?? URL(fileURLWithPath: "/"))
        }

        var imported: [String] = []
        for src in sources {
            let accessing = src.startAccessingSecurityScopedResource()
            defer { if accessing { src.stopAccessingSecurityScopedResource() } }
            do {
                let newURL = try NoteIO.copyInto(folder: dest, source: src)
                imported.append(relativePath(for: newURL) ?? newURL.lastPathComponent)
            } catch {
                lastError = "Import failed for \(src.lastPathComponent): \(error.localizedDescription)"
            }
        }
        await scan()
        return imported
    }

    @discardableResult
    func duplicate(_ relPath: String) async throws -> String {
        guard let url = self.url(for: relPath) else {
            throw NoteIO.IOError.notFound(root ?? URL(fileURLWithPath: "/"))
        }
        let newURL = try NoteIO.duplicate(url)
        await scan()
        return relativePath(for: newURL) ?? newURL.lastPathComponent
    }

    /// Folder URL resolver that accepts "" as root. Distinct from `url(for:)`
    /// which uses `.notDirectory` hint — folders want `.isDirectory`.
    private func folderURL(for relativePath: String) -> URL? {
        guard let root else { return nil }
        if relativePath.isEmpty { return root }
        return root.appending(path: relativePath, directoryHint: .isDirectory)
    }

    // MARK: - Forget

    func forgetVault() {
        accessing?.stopAccessingSecurityScopedResource()
        accessing = nil
        root = nil
        tree = .empty
        VaultBookmark.clear()
    }

    // MARK: - Disk walk

    private static func scanDirectory(
        at url: URL,
        relativePath: String,
        nodeCount: inout Int
    ) -> FolderNode {
        let name = relativePath.isEmpty ? url.lastPathComponent : (url.lastPathComponent)

        var children: [FolderNode] = []

        guard nodeCount < maxNodes else {
            return FolderNode(
                id: relativePath,
                relativePath: relativePath,
                name: name,
                isDirectory: true,
                children: []
            )
        }

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return FolderNode(
                id: relativePath,
                relativePath: relativePath,
                name: name,
                isDirectory: true,
                children: []
            )
        }

        let sorted = entries.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        for entry in sorted {
            guard nodeCount < maxNodes else { break }

            let entryName = entry.lastPathComponent
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDir {
                if skippedDirs.contains(entryName) { continue }
                let childRel = relativePath.isEmpty ? entryName : "\(relativePath)/\(entryName)"
                nodeCount += 1
                let childNode = scanDirectory(
                    at: entry,
                    relativePath: childRel,
                    nodeCount: &nodeCount
                )
                children.append(childNode)
            } else {
                // Notes section whitelist: .md only + images (for markdown embeds).
                // EPUB / music / video are routed to their own sidebar sections via
                // BookLibrary + MediaCatalog and intentionally omitted here.
                let ext = entry.pathExtension.lowercased()
                let isNote = ext == "md"
                let isImage = Self.imageExts.contains(ext)
                guard isNote || isImage else { continue }
                let childRel = relativePath.isEmpty ? entryName : "\(relativePath)/\(entryName)"
                nodeCount += 1
                children.append(FolderNode(
                    id: childRel,
                    relativePath: childRel,
                    name: entryName,
                    isDirectory: false,
                    children: []
                ))
            }
        }

        return FolderNode(
            id: relativePath,
            relativePath: relativePath,
            name: name,
            isDirectory: true,
            children: children
        )
    }
}

// NSOpenPanel async sugar — the standard beginSheet completion handler wrapper.
private extension NSOpenPanel {
    func beginSheet() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            self.begin { response in
                continuation.resume(returning: response)
            }
        }
    }
}
