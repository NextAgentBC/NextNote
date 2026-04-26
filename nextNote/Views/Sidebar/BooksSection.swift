import SwiftUI
import SwiftData

/// Books section — rendered inside LibrarySidebar's Ebooks tray. Lists
/// imported books grouped by their first-level subfolder under the
/// Ebooks root, plus disk-discovered empty folders the user has just
/// created. Header offers New Folder; folder rows have rename / delete /
/// reveal in their context menu; book rows have a Move to ▶ menu and
/// can be dragged onto any folder row.
struct BooksSection: View {
    let books: [Book]

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vaultEnv: VaultStore
    @EnvironmentObject private var libraryRoots: LibraryRoots
    @State private var expandedFolders: Set<String> = []
    @State private var diskFolders: [String] = []
    @State private var dropTargetFolder: String?

    // Alert state
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var renameTarget: String?
    @State private var renameText: String = ""
    @State private var deleteTarget: String?
    @State private var folderError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            let groups = folderGroups()
            ForEach(groups, id: \.folder) { group in
                if group.folder.isEmpty {
                    // Loose books — render directly without a folder header.
                    ForEach(group.books) { book in
                        bookRow(book, indent: 10)
                    }
                } else {
                    folderGroupView(group)
                }
            }
        }
        .task {
            refreshDiskFolders()
            reconcileBookPaths()
        }
        .onReceive(libraryRoots.$ebooksRoot) { _ in
            refreshDiskFolders()
            reconcileBookPaths()
        }
        .alert("New Ebooks Folder", isPresented: $showNewFolderAlert) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") { commitNewFolder() }
        }
        .alert("Rename Folder", isPresented: .init(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("New name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") { commitRenameFolder() }
        } message: {
            Text(renameTarget.map { "Renaming \"\($0)\"" } ?? "")
        }
        .alert("Delete Folder?", isPresented: .init(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) { commitDeleteFolder() }
        } message: {
            Text(deleteTarget.map { "Folder \"\($0)\" must be empty before it can be deleted." } ?? "")
        }
        .alert("Folder Error", isPresented: .init(
            get: { folderError != nil },
            set: { if !$0 { folderError = nil } }
        )) {
            Button("OK") { folderError = nil }
        } message: {
            Text(folderError ?? "")
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Spacer()
            Button {
                tidyWithClaude()
            } label: {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Tidy with Claude — route loose books into existing folders")
            .disabled(libraryRoots.ebooksRoot == nil)

            Button {
                newFolderName = ""
                showNewFolderAlert = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("New Ebooks Folder")
            .padding(.trailing, 10)
        }
        .padding(.vertical, 2)
    }

    /// Drop a pre-baked prompt into the embedded terminal so Claude CLI
    /// can scan the ebooks root, propose a routing plan, and execute it
    /// after explicit confirmation. Drag-drop in the sidebar is fragile
    /// for the long-tail (file paths with non-ASCII characters, drag
    /// session edge cases) — this is the reliable escape hatch.
    private func tidyWithClaude() {
        guard let root = libraryRoots.ebooksRoot else { return }
        let prompt = TidyEbooksPrompt.build(rootPath: root.path)
        appState.showTerminal = true
        appState.pendingTerminalCommand = "claude " + shellEscape(prompt)
    }

    private func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Grouping

    private struct FolderGroup {
        let folder: String
        let books: [Book]
    }

    /// Books grouped by first-level subfolder, merged with disk-discovered
    /// folders so empty user-created folders still show.
    private func folderGroups() -> [FolderGroup] {
        var bucket: [String: [Book]] = [:]
        for b in books {
            bucket[folderKey(for: b), default: []].append(b)
        }
        // Ensure every disk folder appears even with zero books.
        for f in diskFolders where bucket[f] == nil {
            bucket[f] = []
        }
        let ordered = bucket.keys.sorted { a, b in
            if a.isEmpty { return false }
            if b.isEmpty { return true }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        return ordered.map { FolderGroup(folder: $0, books: bucket[$0] ?? []) }
    }

    private func folderKey(for book: Book) -> String {
        guard let url = EPUBImporter.resolveFileURL(book.relativePath, vault: vaultEnv),
              let root = libraryRoots.ebooksRoot
        else { return "" }
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return "" }
        var rel = String(filePath.dropFirst(rootPath.count))
        if rel.hasPrefix("/") { rel.removeFirst() }
        let segs = rel.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return segs.count >= 2 ? segs[0] : ""
    }

    @ViewBuilder
    private func folderGroupView(_ group: FolderGroup) -> some View {
        let expanded = expandedFolders.contains(group.folder)
        let isDropTarget = dropTargetFolder == group.folder

        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                if expanded { expandedFolders.remove(group.folder) }
                else { expandedFolders.insert(group.folder) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(group.folder)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("\(group.books.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .background(isDropTarget ? Color.accentColor.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            dropTargetFolder = nil
            for url in urls {
                let stdPath = url.standardizedFileURL.path
                if let book = books.first(where: {
                    EPUBImporter.resolveFileURL($0.relativePath, vault: vaultEnv)?
                        .standardizedFileURL.path == stdPath
                }) {
                    moveBook(book, toFolder: group.folder)
                }
            }
            return true
        } isTargeted: { active in
            dropTargetFolder = active ? group.folder : (dropTargetFolder == group.folder ? nil : dropTargetFolder)
        }
        .contextMenu {
            Button("Rename…") {
                renameTarget = group.folder
                renameText = group.folder
            }
            Button("Reveal in Finder") { revealFolderInFinder(group.folder) }
            Divider()
            Button("Delete", role: .destructive) {
                deleteTarget = group.folder
            }
            .disabled(!group.books.isEmpty)
        }

        if expanded {
            ForEach(group.books) { book in
                bookRow(book, indent: 24)
            }
        }
    }

    @ViewBuilder
    private func bookRow(_ book: Book, indent: CGFloat = 10) -> some View {
        let isActive = appState.activeBookID == book.id

        HStack(spacing: 6) {
            Image(systemName: "book.closed")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(book.title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer()
        }
        .foregroundStyle(isActive ? Color.accentColor : .primary)
        .padding(.vertical, 3)
        .padding(.leading, indent)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
        .onTapGesture { openBook(book) }
        .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
        .draggable(EPUBImporter.resolveFileURL(book.relativePath, vault: vaultEnv) ?? URL(fileURLWithPath: "/"))
        .contextMenu {
            Button("Reveal in Finder") { revealInFinder(book) }
            Button("Refresh Table of Contents") { refreshTOC(book) }
            Divider()
            Menu("Move to") {
                Button("Root (loose)") { moveBook(book, toFolder: "") }
                Divider()
                ForEach(allFolders(), id: \.self) { name in
                    Button(name) { moveBook(book, toFolder: name) }
                        .disabled(folderKey(for: book) == name)
                }
                Divider()
                Button("New Folder…") {
                    newFolderName = ""
                    showNewFolderAlert = true
                }
            }
            Divider()
            Button("Remove from Library", role: .destructive) { remove(book) }
        }
    }

    // MARK: - Actions

    private func openBook(_ book: Book) {
        appState.openBookTab(bookID: book.id, title: book.title)
        appState.pendingBookAnchor = nil
    }

    private func revealInFinder(_ book: Book) {
        FinderActions.reveal(EPUBImporter.resolveFileURL(book.relativePath, vault: vaultEnv))
    }

    private func revealFolderInFinder(_ folder: String) {
        guard let root = libraryRoots.ebooksRoot else { return }
        FinderActions.reveal(root.appendingPathComponent(folder, isDirectory: true))
    }

    private func refreshTOC(_ book: Book) {
        _ = EPUBImporter.refreshMetadata(book, vault: vaultEnv)
        try? modelContext.save()
    }

    private func remove(_ book: Book) {
        let bookID = book.id
        appState.closeBookTabs(bookID: bookID)
        let hDescriptor = FetchDescriptor<BookHighlight>(
            predicate: #Predicate { $0.bookID == bookID }
        )
        if let highlights = try? modelContext.fetch(hDescriptor) {
            for h in highlights { modelContext.delete(h) }
        }
        modelContext.delete(book)
        try? modelContext.save()
        let unzipDir = EPUBImporter.unzipDir(for: bookID)
        try? FileManager.default.removeItem(at: unzipDir)
    }

    private func commitNewFolder() {
        let name = newFolderName
        newFolderName = ""
        guard let root = libraryRoots.ebooksRoot else {
            folderError = EbookLibraryActions.ActionError.noRoot.localizedDescription
            return
        }
        do {
            _ = try EbookLibraryActions.createFolder(named: name, under: root)
            refreshDiskFolders()
        } catch {
            folderError = error.localizedDescription
        }
    }

    private func commitRenameFolder() {
        guard let old = renameTarget else { return }
        let new = renameText
        renameTarget = nil
        guard let root = libraryRoots.ebooksRoot else {
            folderError = EbookLibraryActions.ActionError.noRoot.localizedDescription
            return
        }
        do {
            try EbookLibraryActions.renameFolder(
                from: old,
                to: new,
                under: root,
                books: books,
                vault: vaultEnv,
                modelContext: modelContext
            )
            // expandedFolders set tracked the old name — migrate.
            if expandedFolders.remove(old) != nil {
                expandedFolders.insert(EbookLibraryActions.sanitize(new) ?? new)
            }
            refreshDiskFolders()
        } catch {
            folderError = error.localizedDescription
        }
    }

    private func commitDeleteFolder() {
        guard let folder = deleteTarget else { return }
        deleteTarget = nil
        guard let root = libraryRoots.ebooksRoot else {
            folderError = EbookLibraryActions.ActionError.noRoot.localizedDescription
            return
        }
        do {
            try EbookLibraryActions.deleteFolder(named: folder, under: root)
            expandedFolders.remove(folder)
            refreshDiskFolders()
        } catch {
            folderError = error.localizedDescription
        }
    }

    private func moveBook(_ book: Book, toFolder folder: String) {
        guard let root = libraryRoots.ebooksRoot else {
            folderError = EbookLibraryActions.ActionError.noRoot.localizedDescription
            return
        }
        do {
            try EbookLibraryActions.moveBook(
                book,
                toFolder: folder,
                root: root,
                vault: vaultEnv,
                modelContext: modelContext
            )
            refreshDiskFolders()
        } catch {
            folderError = error.localizedDescription
        }
    }

    /// Folder names from disk + folders inferred from book paths. Used in
    /// the per-book Move-to menu.
    private func allFolders() -> [String] {
        var set = Set(diskFolders)
        for b in books {
            let k = folderKey(for: b)
            if !k.isEmpty { set.insert(k) }
        }
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func refreshDiskFolders() {
        guard let root = libraryRoots.ebooksRoot else {
            diskFolders = []
            return
        }
        diskFolders = EbookLibraryActions.discoverFolders(under: root)
    }

    /// Sync stale Book.relativePath entries with the actual on-disk
    /// location. Cheap walk of the ebooks tree on every appear / root
    /// change — keeps the sidebar in sync when files were moved out-of-
    /// band (Finder, half-synced drag-drops from earlier builds).
    private func reconcileBookPaths() {
        guard let root = libraryRoots.ebooksRoot else { return }
        _ = EbookLibraryActions.reconcile(
            books: books,
            under: root,
            vault: vaultEnv,
            modelContext: modelContext
        )
    }
}

