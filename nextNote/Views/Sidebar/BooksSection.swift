import SwiftUI
import SwiftData

// Books section — rendered inside LibrarySidebar. Each row expands into its
// TOC; tapping a TOC entry activates the inline reader at that chapter +
// anchor. Purely a view; parent owns the Book array via @Query.
struct BooksSection: View {
    let books: [Book]

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vaultEnv: VaultStore
    @EnvironmentObject private var libraryRoots: LibraryRoots
    @State private var expandedIDs: Set<UUID> = []
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

    // MARK: - Row

    @ViewBuilder
    private func bookRow(_ book: Book, indent: CGFloat = 10) -> some View {
        let isExpanded = expandedIDs.contains(book.id)
        let isActive = appState.activeBookID == book.id

        HStack(spacing: 2) {
            Button {
                toggle(book.id)
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
            .contentShape(Rectangle())
            .onTapGesture { openBook(book) }
        }
        .padding(.vertical, 3)
        .padding(.leading, indent)
        .padding(.trailing, 12)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
        .contextMenu {
            Button("Reveal in Finder") { revealInFinder(book) }
            Button("Refresh Table of Contents") { refreshTOC(book) }
            Divider()
            Button("Remove from Library", role: .destructive) { remove(book) }
        }

        if isExpanded {
            expandedContents(for: book, indent: indent)
        }
    }

    @ViewBuilder
    private func expandedContents(for book: Book, indent: CGFloat = 10) -> some View {
        let toc = decodeTOC(book)
        let spine = decodeSpine(book)
        let tocLeading = indent + 18
        if toc.isEmpty {
            ForEach(Array(spine.enumerated()), id: \.offset) { idx, _ in
                tocLine(
                    title: "Chapter \(idx + 1)",
                    leading: tocLeading,
                    isCurrent: appState.activeBookID == book.id
                        && idx == book.lastChapterIndex
                        && (appState.pendingBookAnchor ?? "").isEmpty,
                    action: { jumpChapter(book: book, index: idx) }
                )
            }
        } else {
            ForEach(flattenTOC(toc)) { row in
                tocLine(
                    title: row.title,
                    leading: tocLeading + CGFloat(row.depth) * 12,
                    isCurrent: appState.activeBookID == book.id
                        && isCurrentTOC(book: book, entry: row, spine: spine),
                    action: { jumpTOC(book: book, href: row.href) }
                )
            }
        }
    }

    @ViewBuilder
    private func tocLine(
        title: String,
        leading: CGFloat,
        isCurrent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
                .lineLimit(2)
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
            Spacer()
        }
        .padding(.leading, leading)
        .padding(.trailing, 12)
        .padding(.vertical, 3)
        .background(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    // MARK: - TOC data

    private struct FlatTOCRow: Identifiable {
        let id: String
        let title: String
        let href: String
        let depth: Int
    }

    private func decodeTOC(_ book: Book) -> [BookTOCEntry] {
        (try? JSONDecoder().decode([BookTOCEntry].self, from: book.tocJSON)) ?? []
    }

    private func decodeSpine(_ book: Book) -> [BookSpineEntry] {
        (try? JSONDecoder().decode([BookSpineEntry].self, from: book.spineJSON)) ?? []
    }

    private func flattenTOC(_ toc: [BookTOCEntry]) -> [FlatTOCRow] {
        var out: [FlatTOCRow] = []
        func walk(_ e: BookTOCEntry, depth: Int) {
            out.append(FlatTOCRow(
                id: "\(out.count)-\(e.href)-\(e.title)",
                title: e.title.isEmpty ? "Untitled" : e.title,
                href: e.href,
                depth: depth
            ))
            for c in e.children { walk(c, depth: depth + 1) }
        }
        for e in toc { walk(e, depth: 0) }
        return out
    }

    private func isCurrentTOC(book: Book, entry: FlatTOCRow, spine: [BookSpineEntry]) -> Bool {
        let clean = entry.href.split(separator: "#").first.map(String.init) ?? entry.href
        let file = (clean as NSString).lastPathComponent
        guard book.lastChapterIndex < spine.count else { return false }
        let sh = spine[book.lastChapterIndex].href
            .split(separator: "#").first.map(String.init) ?? spine[book.lastChapterIndex].href
        return (sh as NSString).lastPathComponent == file
    }

    // MARK: - Actions

    private func toggle(_ id: UUID) {
        if expandedIDs.contains(id) { expandedIDs.remove(id) }
        else { expandedIDs.insert(id) }
    }

    private func openBook(_ book: Book) {
        appState.openBookTab(bookID: book.id, title: book.title)
        appState.pendingBookAnchor = nil
        if !expandedIDs.contains(book.id) {
            expandedIDs.insert(book.id)
        }
    }

    private func jumpChapter(book: Book, index: Int) {
        openBook(book)
        if book.lastChapterIndex != index {
            book.lastChapterIndex = index
            book.lastScrollRatio = 0
        }
        try? modelContext.save()
    }

    private func jumpTOC(book: Book, href: String) {
        openBook(book)
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = parts.first.map(String.init) ?? href
        let anchor = parts.count > 1 ? String(parts[1]) : ""

        // Anchor-only entry (`#section`) — keep current chapter, jump to anchor.
        if rawPath.isEmpty {
            appState.pendingBookAnchor = anchor.isEmpty ? nil : anchor
            try? modelContext.save()
            return
        }

        let spine = decodeSpine(book)
        let path = rawPath.removingPercentEncoding ?? rawPath
        let tocFile = (path as NSString).lastPathComponent

        // Multi-strategy spine lookup:
        //   1. Full path match after URL-decoding both sides (handles
        //      `Text/cover.xhtml`-style nested entries unambiguously).
        //   2. lastPathComponent match (covers EPUBs where the TOC uses
        //      a different relative prefix than the spine).
        //   3. lastPathComponent match without extension (for the
        //      occasional EPUB where TOC drops `.xhtml`).
        let idx: Int? = {
            let normalizedTOCPath = (path as NSString).standardizingPath
            let tocStem = (tocFile as NSString).deletingPathExtension

            let entries = spine.enumerated().map { (i: Int, e: BookSpineEntry) -> (Int, String, String, String) in
                let raw = e.href.split(separator: "#").first.map(String.init) ?? e.href
                let decoded = raw.removingPercentEncoding ?? raw
                let standardized = (decoded as NSString).standardizingPath
                let last = (decoded as NSString).lastPathComponent
                return (i, standardized, last, (last as NSString).deletingPathExtension)
            }

            if let m = entries.first(where: { $0.1 == normalizedTOCPath }) { return m.0 }
            if let m = entries.first(where: { $0.2 == tocFile }) { return m.0 }
            if !tocStem.isEmpty,
               let m = entries.first(where: { $0.3 == tocStem }) { return m.0 }
            return nil
        }()

        guard let idx else {
            NSLog("[BooksSection] jumpTOC: no spine match for href=\(href) (path=\(path), file=\(tocFile))")
            return
        }

        appState.pendingBookAnchor = anchor.isEmpty ? nil : anchor
        if book.lastChapterIndex != idx {
            book.lastChapterIndex = idx
            book.lastScrollRatio = 0
        } else if !anchor.isEmpty {
            // Same chapter, anchor-only navigation. Force scroll-position
            // reset so onChange of pendingBookAnchor in the reader fires
            // even when the value happens to equal the previous one.
            book.lastScrollRatio = 0
        }
        try? modelContext.save()
    }

    private func revealInFinder(_ book: Book) {
        FinderActions.reveal(EPUBImporter.resolveFileURL(book.relativePath, vault: vaultEnv))
    }

    /// Re-parse TOC + spine from the unzipped EPUB on disk. Useful for
    /// books imported before TOC parsing got robust, or where the EPUB's
    /// nav.xhtml / NCX changed shape after import.
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
