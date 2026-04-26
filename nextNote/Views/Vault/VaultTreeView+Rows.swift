import SwiftUI

extension VaultTreeView {
    var list: some View {
        List(selection: $appState.selectedSidebarPath) {
            ForEach(vault.tree.children) { node in
                nodeRow(node)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: appState.selectedSidebarPath) { _, newPath in
            guard !newPath.isEmpty,
                  let node = VaultTreeView.findNode(matching: newPath, in: vault.tree),
                  !node.isDirectory else { return }
            openNote(node)
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls: urls, into: "", dropOnNode: nil)
            return true
        }
    }

    /// Recursive row — directories render as DisclosureGroup bound to
    /// `expandedPaths` so we can programmatically expand on create.
    /// AnyView wrapper breaks the opaque-return recursion cycle.
    func nodeRow(_ node: FolderNode) -> AnyView {
        if node.isDirectory {
            return AnyView(
                DisclosureGroup(
                    isExpanded: expansionBinding(for: node.relativePath)
                ) {
                    ForEach(node.children) { child in
                        nodeRow(child)
                    }
                } label: {
                    row(for: node)
                        .tag(node.relativePath)
                }
            )
        } else {
            return AnyView(
                row(for: node)
                    .tag(node.relativePath)
            )
        }
    }

    func expansionBinding(for path: String) -> Binding<Bool> {
        Binding(
            get: { expandedPaths.contains(path) },
            set: { isExpanded in
                if isExpanded { expandedPaths.insert(path) }
                else { expandedPaths.remove(path) }
            }
        )
    }

    /// Make sure every ancestor folder on `relativePath` is expanded.
    /// Called after create / rename so the new item is visible.
    func expandAncestors(of relativePath: String) {
        var path = (relativePath as NSString).deletingLastPathComponent
        while !path.isEmpty {
            expandedPaths.insert(path)
            let next = (path as NSString).deletingLastPathComponent
            if next == path { break }
            path = next
        }
    }

    @ViewBuilder
    func row(for node: FolderNode) -> some View {
        Group {
            if node.isDirectory {
                Label(node.name, systemImage: node.hasDashboard ? "folder.fill" : "folder")
            } else {
                Label(node.name, systemImage: iconName(for: node))
            }
        }
        .help(node.relativePath)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu { contextMenu(for: node) }
        .draggable(dragURL(for: node) ?? URL(fileURLWithPath: "/"))
        .dropDestination(for: URL.self) { urls, _ in
            let target = node.isDirectory
                ? node.relativePath
                : (node.relativePath as NSString).deletingLastPathComponent
            handleDrop(urls: urls, into: target, dropOnNode: node)
            return true
        }
    }

    func dragURL(for node: FolderNode) -> URL? {
        vault.url(for: node.relativePath)
    }

    func iconName(for node: FolderNode) -> String {
        if node.isDashboard { return "chart.bar.doc.horizontal" }
        let ext = (node.name as NSString).pathExtension.lowercased()
        if let kind = MediaKind.from(ext: ext) { return kind.iconName }
        if VaultStore.imageExts.contains(ext) { return "photo" }
        return "doc.text"
    }

    var emptyVault: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Vault is empty")
                .foregroundStyle(.secondary)
            Text("Drop files here, or create new.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button {
                newNoteParent = ""
                newNoteName = ""
            } label: {
                Label("New Note", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            Button {
                newFolderParent = ""
                newFolderName = ""
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls: urls, into: "", dropOnNode: nil)
            return true
        }
    }

    static func findNode(matching path: String, in tree: FolderNode) -> FolderNode? {
        if tree.relativePath == path { return tree }
        for child in tree.children {
            if child.relativePath == path { return child }
            if let hit = findNode(matching: path, in: child) { return hit }
        }
        return nil
    }
}
