import SwiftUI

extension VaultTreeView {
    func openNote(_ node: FolderNode) {
        guard !node.isDirectory, let fileURL = vault.url(for: node.relativePath) else { return }
        let ext = (node.name as NSString).pathExtension.lowercased()
        let isBinary = MediaKind.from(ext: ext) != nil || VaultStore.imageExts.contains(ext)

        appState.openVaultFile(relativePath: node.relativePath) {
            // Don't try to decode a video/image as UTF-8 — that reads the
            // whole binary into memory just to throw it away. The tab view
            // dispatches on URL extension and ignores the carrier content
            // for media.
            let content = isBinary
                ? ""
                : (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            let title = (node.name as NSString).deletingPathExtension
            return TextDocument(title: title, content: content, fileType: .md)
        }
    }

    func commitCreateNote() {
        guard let parent = newNoteParent else { return }
        let title = newNoteName.trimmingCharacters(in: .whitespacesAndNewlines)
        newNoteParent = nil
        Task {
            do {
                let newPath = try await vault.createNote(inFolder: parent, title: title.isEmpty ? "Untitled" : title)
                expandAncestors(of: newPath)
                openNote(FolderNode(
                    id: newPath,
                    relativePath: newPath,
                    name: (newPath as NSString).lastPathComponent,
                    isDirectory: false,
                    children: []
                ))
                appState.selectedSidebarPath = newPath
            } catch {
                await presentError(error)
            }
        }
    }

    func commitCreateFolder() {
        guard let parent = newFolderParent else { return }
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderParent = nil
        guard !name.isEmpty else { return }
        Task {
            do {
                let newPath = try await vault.createFolder(inParent: parent, name: name)
                expandAncestors(of: newPath)
                expandedPaths.insert(newPath)
                appState.selectedSidebarPath = newPath
            } catch {
                await presentError(error)
            }
        }
    }

    func commitRename() {
        guard let node = renameTarget else { return }
        let text = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        guard !text.isEmpty else { return }
        Task {
            do {
                let newPath = try await vault.rename(node.relativePath, to: text)
                appState.vaultPathChanged(
                    from: node.relativePath,
                    to: newPath,
                    isDirectory: node.isDirectory
                )
                if appState.selectedSidebarPath == node.relativePath {
                    appState.selectedSidebarPath = newPath
                }
                if expandedPaths.remove(node.relativePath) != nil {
                    expandedPaths.insert(newPath)
                }
                expandAncestors(of: newPath)
            } catch {
                await presentError(error)
            }
        }
    }

    func commitDelete() {
        guard let node = deleteTarget else { return }
        deleteTarget = nil
        Task {
            do {
                try await vault.delete(node.relativePath)
                appState.vaultPathDeleted(node.relativePath, isDirectory: node.isDirectory)
                if appState.selectedSidebarPath == node.relativePath {
                    appState.selectedSidebarPath = ""
                }
            } catch {
                await presentError(error)
            }
        }
    }

    @MainActor
    func presentError(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    /// Accept a batch of URLs dropped on the sidebar. URLs already inside
    /// the vault are MOVED (in-sidebar reorg); URLs outside the vault are
    /// COPIED (Finder import). Mixed batches are OK — each URL is routed
    /// by where it came from.
    func handleDrop(urls: [URL], into targetRelPath: String, dropOnNode: FolderNode?) {
        guard !urls.isEmpty else { return }

        var internalMoves: [(relPath: String, isDirectory: Bool)] = []
        var externalCopies: [URL] = []

        for url in urls {
            if let rel = vault.relativePath(for: url), !rel.isEmpty {
                let currentParent = (rel as NSString).deletingLastPathComponent
                if currentParent == targetRelPath { continue }

                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

                if isDir.boolValue {
                    let prefix = rel.hasSuffix("/") ? rel : rel + "/"
                    if targetRelPath == rel || targetRelPath.hasPrefix(prefix) {
                        continue
                    }
                }

                internalMoves.append((rel, isDir.boolValue))
            } else {
                externalCopies.append(url)
            }
        }

        Task {
            var focus: String?
            for move in internalMoves {
                do {
                    let newPath = try await vault.move(move.relPath, toFolder: targetRelPath)
                    appState.vaultPathChanged(
                        from: move.relPath,
                        to: newPath,
                        isDirectory: move.isDirectory
                    )
                    focus = newPath
                } catch {
                    await presentError(error)
                }
            }
            if !externalCopies.isEmpty {
                do {
                    let imported = try await vault.importFiles(externalCopies, intoFolder: targetRelPath)
                    if let first = imported.first { focus = first }
                } catch {
                    await presentError(error)
                }
            }
            if let focus {
                expandAncestors(of: focus)
                appState.selectedSidebarPath = focus
            }
        }
    }

    /// Build `![name](relative/path)` against the *active note's* directory
    /// and put it on the clipboard. Falls back to a vault-root-relative path
    /// if no note is currently active.
    func copyEmbed(for node: FolderNode) {
        let title = (node.name as NSString).deletingPathExtension
        let src: String
        if let activeTabId = appState.activeTabId,
           let activeRel = appState.vaultPath(forTabId: activeTabId) {
            let activeDir = (activeRel as NSString).deletingLastPathComponent
            src = relativePath(from: activeDir, to: node.relativePath)
        } else {
            src = node.relativePath
        }
        PasteboardActions.copyMarkdownEmbed(title: title, path: src)
    }

    /// Pure-string path math: compute a POSIX relative path between two
    /// vault-relative paths. "" = vault root.
    func relativePath(from baseDir: String, to target: String) -> String {
        let baseParts = baseDir.isEmpty ? [] : baseDir.split(separator: "/").map(String.init)
        let targetParts = target.split(separator: "/").map(String.init)
        var common = 0
        while common < baseParts.count && common < targetParts.count
              && baseParts[common] == targetParts[common] {
            common += 1
        }
        let upLevels = baseParts.count - common
        let down = Array(targetParts[common...])
        let parts = Array(repeating: "..", count: upLevels) + down
        return parts.joined(separator: "/")
    }
}
