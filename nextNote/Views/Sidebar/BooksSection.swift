import SwiftUI
import SwiftData

// Books section — rendered inside LibrarySidebar. Lists imported EPUBs
// grouped by their first-level subfolder under the Ebooks root. Tap a
// row to open the book; the table of contents lives in the reader's
// own drawer (toolbar 📋 button) so chapter navigation isn't tangled
// up with cross-process TOC↔spine string-matching.
struct BooksSection: View {
    let books: [Book]

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vaultEnv: VaultStore
    @EnvironmentObject private var libraryRoots: LibraryRoots
    @State private var expandedFolders: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
    }

    private struct FolderGroup {
        let folder: String
        let books: [Book]
    }

    private func folderGroups() -> [FolderGroup] {
        var bucket: [String: [Book]] = [:]
        for b in books {
            bucket[folderKey(for: b), default: []].append(b)
        }
        let ordered = bucket.keys.sorted { a, b in
            if a.isEmpty { return false }
            if b.isEmpty { return true }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        return ordered.map { FolderGroup(folder: $0, books: bucket[$0] ?? []) }
    }

    /// First directory segment between the Ebooks root and the book file,
    /// e.g. a book at `<ebooks>/SciFi/dune.epub` returns "SciFi". Books
    /// that sit directly at the root (or whose resolved path is outside
    /// the root) return "" — rendered flat.
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

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
        .contextMenu {
            Button("Reveal in Finder") { revealInFinder(book) }
            Button("Refresh Table of Contents") { refreshTOC(book) }
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

    /// Re-parse TOC + spine from the unzipped EPUB on disk. Useful when
    /// the EPUB on disk changes (publisher reissue, manual replace).
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
}
