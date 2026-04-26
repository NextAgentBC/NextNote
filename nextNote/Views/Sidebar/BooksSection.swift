import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

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

    // Semantic search
    @State private var searchQuery: String = ""
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var isSearchActive: Bool = false

    // Alert state
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var renameTarget: String?
    @State private var renameText: String = ""
    @State private var deleteTarget: String?
    @State private var folderError: String?

    // Tidy with AI state
    @State private var isTidying = false
    @State private var tidyProposals: [(book: Book, suggestedFolder: String)] = []
    @State private var tidySelections: Set<UUID> = []
    @State private var showTidySheet = false

    // Per-book AI suggestion confirm state
    @State private var suggestionTarget: Book? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            semanticSearchBar
            if isSearchActive {
                semanticResultsList
            } else {
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
            } // end else (not searching)
        }
        .task {
            refreshDiskFolders()
            reconcileBookPaths()
            appState.semanticSearch.updateBookCache(books)
        }
        .onChange(of: books) { _, newBooks in
            appState.semanticSearch.updateBookCache(newBooks)
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
        .sheet(isPresented: $showTidySheet) {
            tidySheet
        }
        .sheet(item: $suggestionTarget) { book in
            aiSuggestionSheet(for: book)
        }
    }

    // MARK: - Semantic Search

    private var semanticSearchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Search content…", text: $searchQuery)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
                .onChange(of: searchQuery) { _, newValue in
                    searchTask?.cancel()
                    let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if query.isEmpty {
                        isSearchActive = false
                        return
                    }
                    isSearchActive = true
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }
                        try? await appState.semanticSearch.search(query: query)
                    }
                }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    isSearchActive = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var semanticResultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.semanticSearch.isSearching {
                HStack {
                    ProgressView().controlSize(.mini)
                    Text("Searching…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            } else if appState.semanticSearch.results.isEmpty {
                Text("No results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                ForEach(appState.semanticSearch.results) { result in
                    semanticResultRow(result)
                }
            }
        }
    }

    @ViewBuilder
    private func semanticResultRow(_ result: SearchResult) -> some View {
        Button {
            if let book = result.book {
                appState.openBookTab(bookID: book.id, title: book.title)
                appState.pendingBookAnchor = nil
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(result.documentTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f%%", result.similarity * 100))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Text(result.chunkContent)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Spacer()
            Button {
                tidyWithAI()
            } label: {
                if isTidying {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Tidy with AI — suggest folders for loose books")
            .disabled(libraryRoots.ebooksRoot == nil || isTidying)

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

    private func tidyWithAI() {
        guard let root = libraryRoots.ebooksRoot else { return }
        isTidying = true
        let existingFolders = EbookLibraryActions.discoverFolders(under: root)
        let ai = appState.aiService
        let booksToTidy = books
        Task { @MainActor in
            let proposals = (try? await FolderCategorizer.batchSuggest(
                books: booksToTidy,
                existingFolders: existingFolders,
                ai: ai
            )) ?? []
            tidyProposals = proposals.filter { folderKey(for: $0.book) != $0.suggestedFolder }
            tidySelections = Set(tidyProposals.map { $0.book.id })
            isTidying = false
            if !tidyProposals.isEmpty { showTidySheet = true }
        }
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

        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(book.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer()
            }
            if let suggestion = book.aiSuggestion, let suggestedTitle = suggestion.title {
                Button {
                    suggestionTarget = book
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                        Text(suggestedTitle)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.leading, 17)
            }
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
            Button("Locate File…") { locateFile(for: book) }
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
            // Auto-recovery: maybe Book.relativePath is just stale.
            // Run reconcile then retry once.
            let fixed = EbookLibraryActions.reconcile(
                books: books,
                under: root,
                vault: vaultEnv,
                modelContext: modelContext
            )
            if fixed > 0 {
                do {
                    try EbookLibraryActions.moveBook(
                        book,
                        toFolder: folder,
                        root: root,
                        vault: vaultEnv,
                        modelContext: modelContext
                    )
                    refreshDiskFolders()
                    return
                } catch {
                    folderError = error.localizedDescription + "\n\nIf the file is somewhere unexpected, right-click the book → Locate File… to point nextNote at it."
                    return
                }
            }
            folderError = error.localizedDescription + "\n\nIf the file is somewhere unexpected, right-click the book → Locate File… to point nextNote at it."
        }
    }

    /// Open a file picker so the user can manually relink a Book record
    /// to its actual on-disk file. Useful when reconcile can't auto-find
    /// it (filename was changed, file lives outside ebooksRoot, etc).
    private func locateFile(for book: Book) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var allowed: [UTType] = [.pdf]
        if let epubType = UTType(filenameExtension: "epub") { allowed.append(epubType) }
        panel.allowedContentTypes = allowed
        panel.message = "Pick the actual file for \"\(book.title)\"."
        panel.prompt = "Relink"
        panel.runModal()
        guard let url = panel.url else { return }
        book.relativePath = vaultEnv.relativePath(for: url) ?? url.path
        try? modelContext.save()
        refreshDiskFolders()
        #endif
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

    private func reconcileBookPaths() {
        guard let root = libraryRoots.ebooksRoot else { return }
        _ = EbookLibraryActions.reconcile(
            books: books,
            under: root,
            vault: vaultEnv,
            modelContext: modelContext
        )
    }

    // MARK: - Tidy sheet

    @ViewBuilder
    private var tidySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tidy with AI")
                .font(.headline)
            Text("AI suggested folders for \(tidyProposals.count) book(s). Check the moves you want to apply.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            List(tidyProposals, id: \.book.id) { proposal in
                HStack {
                    Toggle(isOn: Binding(
                        get: { tidySelections.contains(proposal.book.id) },
                        set: { on in
                            if on { tidySelections.insert(proposal.book.id) }
                            else { tidySelections.remove(proposal.book.id) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(proposal.book.title)
                                .font(.system(size: 13))
                            HStack(spacing: 4) {
                                Text(folderKey(for: proposal.book).isEmpty ? "(root)" : folderKey(for: proposal.book))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(proposal.suggestedFolder)
                                    .foregroundStyle(Color.accentColor)
                            }
                            .font(.system(size: 11))
                        }
                    }
                }
            }

            HStack {
                Button("Cancel") { showTidySheet = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply \(tidySelections.count) Move(s)") {
                    applyTidyProposals()
                    showTidySheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(tidySelections.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 300)
    }

    private func applyTidyProposals() {
        guard let root = libraryRoots.ebooksRoot else { return }
        for proposal in tidyProposals where tidySelections.contains(proposal.book.id) {
            do {
                try EbookLibraryActions.moveBook(
                    proposal.book,
                    toFolder: proposal.suggestedFolder,
                    root: root,
                    vault: vaultEnv,
                    modelContext: modelContext
                )
            } catch {
                folderError = error.localizedDescription
            }
        }
        refreshDiskFolders()
    }

    // MARK: - Per-book AI suggestion sheet

    @ViewBuilder
    private func aiSuggestionSheet(for book: Book) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Suggestion")
                .font(.headline)
            if let s = book.aiSuggestion {
                VStack(alignment: .leading, spacing: 8) {
                    if let title = s.title {
                        LabeledContent("Suggested Title", value: title)
                    }
                    if let author = s.author {
                        LabeledContent("Suggested Author", value: author)
                    }
                    if let summary = s.summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Button("Dismiss") {
                    book.aiSuggestion = nil
                    try? modelContext.save()
                    suggestionTarget = nil
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") {
                    if let s = book.aiSuggestion {
                        if let title = s.title, !title.isEmpty { book.title = title }
                        if let author = s.author, !author.isEmpty { book.author = author }
                    }
                    book.aiSuggestion = nil
                    try? modelContext.save()
                    suggestionTarget = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(book.aiSuggestion?.title == nil && book.aiSuggestion?.author == nil)
            }
        }
        .padding()
        .frame(minWidth: 360)
    }
}

