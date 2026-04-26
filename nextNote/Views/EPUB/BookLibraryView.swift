import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Grid of imported EPUBs. Opens the reader on click; right-click offers
// export-to-markdown / reveal / delete. Triggers .fileImporter in-place to
// add new books.
struct BookLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var appState: AppState

    @Query(sort: \Book.lastOpenedAt, order: .reverse) private var books: [Book]

    @State private var isImporterOpen = false
    @State private var errorMessage: String?
    @State private var isImporting = false

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 18)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if books.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(books) { book in
                            BookCoverCell(book: book, vault: vault)
                                .onTapGesture { openReader(book) }
                                .contextMenu {
                                    Button("Open") { openReader(book) }
                                    Button("Reveal in Finder") { revealInFinder(book) }
                                    Divider()
                                    Button("Remove from Library", role: .destructive) { remove(book) }
                                }
                        }
                    }
                    .padding(18)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 440)
        .fileImporter(
            isPresented: $isImporterOpen,
            allowedContentTypes: [UTType(filenameExtension: "epub") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): importBooks(urls)
            case .failure: break
            }
        }
        .alert("EPUB error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var toolbar: some View {
        HStack {
            Text("Library")
                .font(.title2.bold())
            Spacer()
            if isImporting {
                ProgressView().controlSize(.small)
            }
            Button {
                isImporterOpen = true
            } label: {
                Label("Import EPUB…", systemImage: "square.and.arrow.down")
            }
            .disabled(vault.root == nil)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(14)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No books yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            if vault.root == nil {
                Text("Pick a vault folder first. EPUBs are stored under <vault>/Books/.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                Button("Import EPUB…") { isImporterOpen = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func openReader(_ book: Book) {
        appState.openBookTab(bookID: book.id, title: book.title)
        dismiss()
    }

    private func importBooks(_ urls: [URL]) {
        guard vault.root != nil else {
            errorMessage = "Choose a vault folder first."
            return
        }
        isImporting = true
        Task {
            defer { Task { @MainActor in isImporting = false } }
            let importer = EPUBImporter(vault: vault, context: modelContext)
            for url in urls {
                do {
                    _ = try await importer.importEPUB(from: url)
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func revealInFinder(_ book: Book) {
        FinderActions.reveal(EPUBImporter.resolveFileURL(book.relativePath, vault: vault))
    }

    private func remove(_ book: Book) {
        let bookID = book.id
        appState.closeBookTabs(bookID: bookID)
        // Delete highlights.
        let hDescriptor = FetchDescriptor<BookHighlight>(
            predicate: #Predicate { $0.bookID == bookID }
        )
        if let highlights = try? modelContext.fetch(hDescriptor) {
            for h in highlights { modelContext.delete(h) }
        }
        modelContext.delete(book)
        try? modelContext.save()

        // Clear unzip cache only — never touch originals on disk for
        // external-root books. Keeps removal reversible.
        let unzipDir = EPUBImporter.unzipDir(for: bookID)
        try? FileManager.default.removeItem(at: unzipDir)
    }
}

private struct BookCoverCell: View {
    let book: Book
    let vault: VaultStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
            Text(book.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
            if let author = book.author, !author.isEmpty {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            progressLine
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var cover: some View {
        if let rel = book.coverRelativePath,
           let url = EPUBImporter.resolveFileURL(rel, vault: vault),
           let nsImage = loadImage(url: url) {
            #if os(macOS)
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
            #else
            Image(uiImage: nsImage)
                .resizable()
                .scaledToFit()
            #endif
        } else {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var progressLine: some View {
        let spine = (try? JSONDecoder().decode([BookSpineEntry].self, from: book.spineJSON)) ?? []
        let total = max(spine.count, 1)
        let pct = Int(Double(book.lastChapterIndex + 1) / Double(total) * 100)
        return Text("Ch \(book.lastChapterIndex + 1)/\(total) · \(pct)%")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    #if os(macOS)
    private func loadImage(url: URL) -> NSImage? {
        NSImage(contentsOf: url)
    }
    #else
    private func loadImage(url: URL) -> UIImage? {
        UIImage(contentsOfFile: url.path)
    }
    #endif
}
