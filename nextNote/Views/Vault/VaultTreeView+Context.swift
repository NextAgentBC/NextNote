import SwiftUI

extension VaultTreeView {
    @ViewBuilder
    func contextMenu(for node: FolderNode) -> some View {
        if node.isDirectory {
            Button { newNoteParent = node.relativePath; newNoteName = "" } label: {
                Label("New Note", systemImage: "doc.badge.plus")
            }
            Button { newFolderParent = node.relativePath; newFolderName = "" } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            Divider()
        } else {
            Button { openNote(node) } label: {
                Label("Open", systemImage: "doc.text")
            }
            if MediaKind.from(ext: (node.name as NSString).pathExtension) != nil {
                Button { copyEmbed(for: node) } label: {
                    Label("Copy as Markdown Embed", systemImage: "doc.on.clipboard")
                }
            }
            Button {
                Task {
                    do {
                        _ = try await vault.duplicate(node.relativePath)
                    } catch {
                        await presentError(error)
                    }
                }
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            Divider()
        }

        Button {
            renameTarget = node
            renameText = node.isDirectory ? node.name : (node.name as NSString).deletingPathExtension
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        #if os(macOS)
        Button {
            FinderActions.reveal(vault.url(for: node.relativePath))
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        #endif

        Divider()
        Button(role: .destructive) {
            deleteTarget = node
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
