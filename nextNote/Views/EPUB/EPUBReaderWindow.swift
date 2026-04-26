import SwiftUI
import SwiftData

// Inline reader host — resolves Book by UUID and mounts EPUBReaderView in
// the main detail pane.
struct EPUBReaderHost: View {
    let bookID: UUID
    @Query private var books: [Book]
    @EnvironmentObject private var appState: AppState

    init(bookID: UUID) {
        self.bookID = bookID
        _books = Query(filter: #Predicate<Book> { $0.id == bookID })
    }

    var body: some View {
        if let book = books.first {
            switch book.kind {
            case .epub:
                EPUBReaderView(book: book)
                    .id(book.id)
            case .pdf:
                #if os(macOS)
                PDFReaderView(book: book)
                    .id(book.id)
                #else
                EPUBReaderView(book: book)
                    .id(book.id)
                #endif
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Book not found.")
                    .foregroundStyle(.secondary)
                Button("Back to Notes") {
                    if let tabID = appState.activeTabId {
                        appState.closeTab(id: tabID)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
