import Foundation
import AppKit
import SwiftUI

/// Persists a list of user-pinned external folders shown in the sidebar
/// alongside the Notes vault. Each entry owns a security-scoped bookmark
/// so access survives relaunch. Trees are rebuilt on adoption and on
/// demand via `rescan(id:)`; scanning runs off-MainActor via
/// `VaultTreeScanner.buildTree(root:)`.
@MainActor
final class PinnedFoldersStore: ObservableObject {
    @Published private(set) var folders: [PinnedFolder] = []

    // Per-folder access tokens — kept alive for as long as the folder is
    // pinned so file reads inside the tree don't need to re-acquire scope.
    private var access: [UUID: URL] = [:]

    private static let defaultsKey = "nextnote.pinnedFolders"

    private struct Record: Codable {
        let id: UUID
        let name: String
        let bookmark: Data
    }

    init() {
        restore()
    }

    deinit {
        for url in access.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Pick

    func pickAndAdd() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add to Sidebar"
        panel.message = "Pick a folder to pin in the sidebar."
        let response = await panel.beginSheet()
        guard response == .OK, let url = panel.url else { return }
        await add(url: url)
    }

    // MARK: - Add / Remove

    @discardableResult
    func add(url: URL) async -> UUID? {
        if let existing = folders.first(where: { $0.url == url }) {
            await rescan(id: existing.id)
            return existing.id
        }
        guard let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }
        let id = UUID()
        let name = url.lastPathComponent
        if url.startAccessingSecurityScopedResource() {
            access[id] = url
        }
        let placeholder = PinnedFolder(
            id: id,
            name: name,
            url: url,
            tree: FolderNode(
                id: "",
                relativePath: "",
                name: name,
                isDirectory: true,
                children: []
            )
        )
        folders.append(placeholder)
        persistAll()
        await rescan(id: id)
        return id
    }

    func remove(id: UUID) {
        if let url = access[id] {
            url.stopAccessingSecurityScopedResource()
        }
        access[id] = nil
        folders.removeAll { $0.id == id }
        persistAll()
    }

    func rename(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[idx].name = trimmed
        // Reflect rename in the tree root so the disclosure label updates.
        var tree = folders[idx].tree
        tree = FolderNode(
            id: tree.id,
            relativePath: tree.relativePath,
            name: trimmed,
            isDirectory: true,
            children: tree.children
        )
        folders[idx].tree = tree
        persistAll()
    }

    // MARK: - Scan

    func rescan(id: UUID) async {
        guard let idx = folders.firstIndex(where: { $0.id == id }) else { return }
        let root = folders[idx].url
        let displayName = folders[idx].name
        let result = await Task.detached(priority: .userInitiated) {
            VaultTreeScanner.buildTree(root: root)
        }.value
        guard let stillIdx = folders.firstIndex(where: { $0.id == id }) else { return }
        let renamedTree = FolderNode(
            id: result.tree.id,
            relativePath: result.tree.relativePath,
            name: displayName,
            isDirectory: true,
            children: result.tree.children
        )
        folders[stillIdx].tree = renamedTree
    }

    func rescanAll() async {
        for folder in folders {
            await rescan(id: folder.id)
        }
    }

    // MARK: - URL resolution

    func url(for id: UUID, relativePath: String) -> URL? {
        guard let folder = folders.first(where: { $0.id == id }) else { return nil }
        if relativePath.isEmpty { return folder.url }
        return folder.url.appending(path: relativePath, directoryHint: .notDirectory)
    }

    // MARK: - Persistence

    private func persistAll() {
        let records: [Record] = folders.compactMap { folder in
            guard let data = try? folder.url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) else { return nil }
            return Record(id: folder.id, name: folder.name, bookmark: data)
        }
        save(records: records)
    }

    private func save(records: [Record]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private func loadRecords() -> [Record] {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return [] }
        return records
    }

    private func restore() {
        let records = loadRecords()
        for record in records {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: record.bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            if url.startAccessingSecurityScopedResource() {
                access[record.id] = url
            }
            let folder = PinnedFolder(
                id: record.id,
                name: record.name,
                url: url,
                tree: FolderNode(
                    id: "",
                    relativePath: "",
                    name: record.name,
                    isDirectory: true,
                    children: []
                )
            )
            folders.append(folder)
            Task { await rescan(id: record.id) }
        }
    }
}

private extension NSOpenPanel {
    func beginSheet() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { cont in
            self.begin { cont.resume(returning: $0) }
        }
    }
}
