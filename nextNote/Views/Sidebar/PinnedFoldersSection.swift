import SwiftUI
import SwiftData

// Sidebar section showing user-pinned external folders. Each entry is its
// own DisclosureGroup with a nested file/folder tree rendered from
// PinnedFoldersStore.folders[i].tree. Clicking a file routes through
// AppState.openExternalFile, which handles md/text via openTextLike and
// pdf/epub via the importer.
struct PinnedFoldersSection: View {
    @EnvironmentObject private var store: PinnedFoldersStore
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.modelContext) private var modelContext

    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var expandedPaths: Set<String> = []
    @State private var renameTarget: PinnedFolder?
    @State private var renameText: String = ""
    @State private var removeTarget: PinnedFolder?

    var body: some View {
        Group {
            if store.folders.isEmpty {
                EmptyView()
            } else {
                content
            }
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                if let target = renameTarget {
                    store.rename(id: target.id, to: renameText)
                }
                renameTarget = nil
            }
        }
        .alert("Remove Folder from Sidebar?", isPresented: Binding(
            get: { removeTarget != nil },
            set: { if !$0 { removeTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { removeTarget = nil }
            Button("Remove", role: .destructive) {
                if let target = removeTarget {
                    store.remove(id: target.id)
                }
                removeTarget = nil
            }
        } message: {
            Text("This only removes it from the sidebar. Files on disk are untouched.")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            List {
                ForEach(store.folders) { folder in
                    folderSection(folder)
                }
            }
            .listStyle(.sidebar)
            .frame(minHeight: 60, maxHeight: 240)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Folders")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await store.pickAndAdd() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Add Folder…")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func folderSection(_ folder: PinnedFolder) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedFolderIDs.contains(folder.id) },
                set: { isExp in
                    if isExp { expandedFolderIDs.insert(folder.id) }
                    else { expandedFolderIDs.remove(folder.id) }
                }
            )
        ) {
            ForEach(folder.tree.children) { node in
                nodeRow(folder: folder, node: node)
            }
        } label: {
            Label(folder.name, systemImage: "folder")
                .help(folder.url.path)
                .contextMenu {
                    Button("Rescan") {
                        Task { await store.rescan(id: folder.id) }
                    }
                    Button("Rename…") {
                        renameText = folder.name
                        renameTarget = folder
                    }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([folder.url])
                    }
                    Divider()
                    Button("Remove from Sidebar", role: .destructive) {
                        removeTarget = folder
                    }
                }
        }
    }

    private func nodeRow(folder: PinnedFolder, node: FolderNode) -> AnyView {
        let key = "\(folder.id.uuidString)/\(node.relativePath)"
        if node.isDirectory {
            return AnyView(
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedPaths.contains(key) },
                        set: { isExp in
                            if isExp { expandedPaths.insert(key) }
                            else { expandedPaths.remove(key) }
                        }
                    )
                ) {
                    ForEach(node.children) { child in
                        nodeRow(folder: folder, node: child)
                    }
                } label: {
                    Label(node.name, systemImage: "folder")
                        .help(node.relativePath)
                }
            )
        } else {
            return AnyView(
                Label(node.name, systemImage: iconName(for: node))
                    .help(node.relativePath)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { openFile(folder: folder, node: node) }
            )
        }
    }

    private func openFile(folder: PinnedFolder, node: FolderNode) {
        guard !node.isDirectory,
              let fileURL = store.url(for: folder.id, relativePath: node.relativePath)
        else { return }
        appState.openExternalFile(url: fileURL, vault: vault, context: modelContext)
    }

    private func iconName(for node: FolderNode) -> String {
        let ext = (node.name as NSString).pathExtension.lowercased()
        if let kind = MediaKind.from(ext: ext) { return kind.iconName }
        if VaultStore.imageExts.contains(ext) { return "photo" }
        return "doc.text"
    }
}
