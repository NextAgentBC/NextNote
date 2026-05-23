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
                    newNote(in: NewDocumentRouter.targetFolder(
                        forSelection: appState.selectedSidebarPath, in: vault.tree))
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
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
        #if os(macOS)
        ToolbarItem(placement: .automatic) {
            Button {
                openPDFFromDisk()
            } label: {
                Image(systemName: "doc.viewfinder")
            }
            .help("Open a PDF to annotate")
            .disabled(vault.root == nil)
        }
        #endif
        ToolbarItem(placement: .automatic) {
            Button {
                Task { await vault.scan() }
                // Also kick the media + ebook libraries — user clicking
                // the sidebar refresh button after a Tidy / Finder move
                // expects everything to update, not just notes.
                appState.triggerRescanLibrary = true
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Rescan vault + media + ebooks")
            .disabled(vault.isScanning || vault.root == nil)
        }
    }
}
