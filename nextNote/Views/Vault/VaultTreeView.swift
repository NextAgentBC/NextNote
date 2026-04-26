import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Sidebar hierarchy driven by `VaultStore.tree`. Replaces FileListView when
/// vaultMode is on. Click a file to open as a tab. Toolbar / row / actions /
/// context menu live in adjacent extension files.
struct VaultTreeView: View {
    @EnvironmentObject var vault: VaultStore
    @EnvironmentObject var appState: AppState

    // Rename / delete flow state. Path is vault-relative.
    @State var renameTarget: FolderNode?
    @State var renameText: String = ""
    @State var deleteTarget: FolderNode?
    @State var newNoteParent: String?      // "" = root; nil = sheet hidden
    @State var newNoteName: String = ""
    @State var newFolderParent: String?
    @State var newFolderName: String = ""
    @State var errorMessage: String?
    /// Folder paths the user (or code) has expanded. Starts empty — top
    /// level is always "rendered" since we iterate `tree.children` directly.
    @State var expandedPaths: Set<String> = []

    var body: some View {
        Group {
            if vault.root == nil {
                VaultPickerView()
            } else if vault.tree.children.isEmpty && !vault.isScanning {
                emptyVault
            } else {
                list
            }
        }
        .toolbar { treeToolbar }
        .alert("Rename", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") { commitRename() }
        } message: {
            Text(renameTarget?.isDirectory == true ? "New folder name" : "New file name (extension optional)")
        }
        .alert("Delete", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Move to Trash", role: .destructive) { commitDelete() }
        } message: {
            if let t = deleteTarget {
                Text("\"\(t.name)\" will be moved to the Trash. You can restore it from there.")
            }
        }
        .alert("New Note", isPresented: Binding(
            get: { newNoteParent != nil },
            set: { if !$0 { newNoteParent = nil } }
        )) {
            TextField("Title", text: $newNoteName)
            Button("Cancel", role: .cancel) { newNoteParent = nil }
            Button("Create") { commitCreateNote() }
        } message: {
            Text(newNoteParent.map { $0.isEmpty ? "In vault root" : "In \($0)" } ?? "")
        }
        .alert("New Folder", isPresented: Binding(
            get: { newFolderParent != nil },
            set: { if !$0 { newFolderParent = nil } }
        )) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderParent = nil }
            Button("Create") { commitCreateFolder() }
        } message: {
            Text(newFolderParent.map { $0.isEmpty ? "In vault root" : "In \($0)" } ?? "")
        }
        .alert("Vault Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
