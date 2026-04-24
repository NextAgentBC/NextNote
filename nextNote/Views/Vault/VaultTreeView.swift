import SwiftUI
#if os(macOS)
import AppKit
#endif

// Sidebar hierarchy driven by VaultStore.tree. Replaces FileListView when
// vaultMode is on. Click a file to open as a tab. Context menu and toolbar
// buttons cover create / rename / duplicate / delete + reveal in Finder.
struct VaultTreeView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var appState: AppState

    // Rename / delete flow state. Path is vault-relative.
    @State private var renameTarget: FolderNode?
    @State private var renameText: String = ""
    @State private var deleteTarget: FolderNode?
    @State private var newNoteParent: String?      // "" = root; nil = sheet hidden
    @State private var newNoteName: String = ""
    @State private var newFolderParent: String?
    @State private var newFolderName: String = ""
    @State private var errorMessage: String?
    /// Folder paths the user (or code) has expanded. Starts empty — top
    /// level is always "rendered" since we iterate `tree.children` directly.
    @State private var expandedPaths: Set<String> = []

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
        // Title moved to the detail pane so the window shows the active
        // note / book title instead of the vault folder name.
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var treeToolbar: some ToolbarContent {
        // Single "+" Menu holding both New Note and New Folder — keeps the
        // sidebar toolbar compact so neither action hides in the overflow
        // chevron on narrow window widths.
        ToolbarItem(placement: .automatic) {
            Menu {
                Button {
                    newNoteParent = targetFolderPath()
                    newNoteName = ""
                } label: {
                    Label("New Note", systemImage: "doc.badge.plus")
                }
                Button {
                    newFolderParent = targetFolderPath()
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

    // MARK: - List

    private var list: some View {
        List(selection: $appState.selectedSidebarPath) {
            ForEach(vault.tree.children) { node in
                nodeRow(node)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: appState.selectedSidebarPath) { _, newPath in
            guard !newPath.isEmpty,
                  let node = findNode(matching: newPath, in: vault.tree),
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
    private func nodeRow(_ node: FolderNode) -> AnyView {
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

    private func expansionBinding(for path: String) -> Binding<Bool> {
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
    private func expandAncestors(of relativePath: String) {
        var path = (relativePath as NSString).deletingLastPathComponent
        while !path.isEmpty {
            expandedPaths.insert(path)
            let next = (path as NSString).deletingLastPathComponent
            if next == path { break }
            path = next
        }
    }

    @ViewBuilder
    private func row(for node: FolderNode) -> some View {
        Group {
            if node.isDirectory {
                Label(node.name, systemImage: node.hasDashboard ? "folder.fill" : "folder")
            } else {
                Label(node.name, systemImage: iconName(for: node))
            }
        }
        .help(node.relativePath)
        // Full-row hit area so click+drag has the whole row as its handle,
        // not just the text glyphs.
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu { contextMenu(for: node) }
        // Any row is draggable — its own file URL is what gets dragged. That
        // makes in-sidebar reorg (drop on a folder → move) and drags out to
        // Finder work with the same payload.
        .draggable(dragURL(for: node) ?? URL(fileURLWithPath: "/"))
        // Drop target: Finder drops get copied in; internal drags get moved.
        // Folder rows receive into themselves; file rows route into their
        // parent folder so drops on a sibling land somewhere sensible.
        .dropDestination(for: URL.self) { urls, _ in
            let target = node.isDirectory
                ? node.relativePath
                : (node.relativePath as NSString).deletingLastPathComponent
            handleDrop(urls: urls, into: target, dropOnNode: node)
            return true
        }
    }

    private func dragURL(for node: FolderNode) -> URL? {
        vault.url(for: node.relativePath)
    }

    private func iconName(for node: FolderNode) -> String {
        if node.isDashboard { return "chart.bar.doc.horizontal" }
        let ext = (node.name as NSString).pathExtension.lowercased()
        if let kind = MediaKind.from(ext: ext) { return kind.iconName }
        if VaultStore.imageExts.contains(ext) { return "photo" }
        return "doc.text"
    }

    @ViewBuilder
    private func contextMenu(for node: FolderNode) -> some View {
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
            if let url = vault.url(for: node.relativePath) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
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

    private var emptyVault: some View {
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

    // MARK: - Actions

    private func openNote(_ node: FolderNode) {
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

    private func commitCreateNote() {
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

    private func commitCreateFolder() {
        guard let parent = newFolderParent else { return }
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderParent = nil
        guard !name.isEmpty else { return }
        Task {
            do {
                let newPath = try await vault.createFolder(inParent: parent, name: name)
                expandAncestors(of: newPath)
                // Expand the new folder itself so it's visibly "open" when
                // the tree scan finishes.
                expandedPaths.insert(newPath)
                appState.selectedSidebarPath = newPath
            } catch {
                await presentError(error)
            }
        }
    }

    private func commitRename() {
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
                // Carry over the expansion state so the renamed folder
                // doesn't snap shut.
                if expandedPaths.remove(node.relativePath) != nil {
                    expandedPaths.insert(newPath)
                }
                expandAncestors(of: newPath)
            } catch {
                await presentError(error)
            }
        }
    }

    private func commitDelete() {
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
    private func presentError(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    /// Accept a batch of URLs dropped on the sidebar. URLs already inside
    /// the vault are MOVED (in-sidebar reorg); URLs outside the vault are
    /// COPIED (Finder import). Mixed batches are OK — each URL is routed
    /// by where it came from.
    ///
    /// `dropOnNode` is the node directly under the pointer (nil = list/root);
    /// it's used to block pathological moves like dropping a folder onto
    /// itself or its own descendants.
    private func handleDrop(urls: [URL], into targetRelPath: String, dropOnNode: FolderNode?) {
        guard !urls.isEmpty else { return }

        var internalMoves: [(relPath: String, isDirectory: Bool)] = []
        var externalCopies: [URL] = []

        for url in urls {
            if let rel = vault.relativePath(for: url), !rel.isEmpty {
                // Skip no-op: dropping a file onto its current parent.
                let currentParent = (rel as NSString).deletingLastPathComponent
                if currentParent == targetRelPath { continue }

                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

                // Block dropping a folder into itself or its descendants.
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
    /// if no note is currently active — user can still paste and it'll work
    /// from notes at vault root.
    private func copyEmbed(for node: FolderNode) {
        let title = (node.name as NSString).deletingPathExtension
        let src: String
        if let activeTabId = appState.activeTabId,
           let activeRel = appState.vaultPath(forTabId: activeTabId) {
            let activeDir = (activeRel as NSString).deletingLastPathComponent
            src = relativePath(from: activeDir, to: node.relativePath)
        } else {
            src = node.relativePath
        }
        let markdown = "![\(title)](\(src))"

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        #endif
    }

    /// Pure-string path math: compute a POSIX relative path between two
    /// vault-relative paths. "" = vault root.
    private func relativePath(from baseDir: String, to target: String) -> String {
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

    /// Resolve the "active folder" for New Note / New Folder. If the sidebar
    /// selection is a file, use its parent directory. If it's a folder, use
    /// it directly. Fallback: vault root.
    private func targetFolderPath() -> String {
        let sel = appState.selectedSidebarPath
        if sel.isEmpty { return "" }
        if let node = findNode(matching: sel, in: vault.tree) {
            return node.isDirectory ? sel : (sel as NSString).deletingLastPathComponent
        }
        return ""
    }

    private func findNode(matching path: String, in tree: FolderNode) -> FolderNode? {
        if tree.relativePath == path { return tree }
        for child in tree.children {
            if child.relativePath == path { return child }
            if let hit = findNode(matching: path, in: child) { return hit }
        }
        return nil
    }
}
