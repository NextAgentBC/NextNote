import SwiftUI

extension VaultTreeView {
    @ToolbarContentBuilder
    var treeToolbar: some ToolbarContent {
        // Single "+" Menu holding both New Note and New Folder — keeps the
        // sidebar toolbar compact so neither action hides in the overflow
        // chevron on narrow window widths.
        ToolbarItem(placement: .automatic) {
            Menu {
                Button {
                    newNoteParent = NewDocumentRouter.targetFolder(
                        forSelection: appState.selectedSidebarPath,
                        in: vault.tree
                    )
                    newNoteName = ""
                } label: {
                    Label("New Note", systemImage: "doc.badge.plus")
                }
                Button {
                    newFolderParent = NewDocumentRouter.targetFolder(
                        forSelection: appState.selectedSidebarPath,
                        in: vault.tree
                    )
                    newFolderName = ""
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuIndicator(.hidden)
            .help("New Note / Folder")
            .disabled(vault.root == nil)
        }
        ToolbarItem(placement: .automatic) {
            Button {
                Task { await vault.scan() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Rescan vault")
            .disabled(vault.isScanning || vault.root == nil)
        }
    }
}
