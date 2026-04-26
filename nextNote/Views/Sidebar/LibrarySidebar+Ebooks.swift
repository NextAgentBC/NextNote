import SwiftUI

extension LibrarySidebar {
    var ebooksTray: some View {
        VStack(alignment: .leading, spacing: 0) {
            trayHeader(
                title: "Ebooks",
                icon: "books.vertical",
                count: books.count,
                expanded: $ebooksExpanded
            )
            .contextMenu {
                Button("Rescan Ebooks Folder") {
                    appState.triggerRescanLibrary = true
                }
            }
            // First-expand kicks a fresh BookLibrary scan so PDFs / EPUBs
            // dropped into the folder while the app was running show up
            // without a manual refresh.
            .onChange(of: ebooksExpanded) { _, isOpen in
                if isOpen { appState.triggerRescanLibrary = true }
            }
            if ebooksExpanded {
                ScrollView {
                    BooksSection(books: books)
                }
                .frame(maxHeight: 260)
            }
        }
    }
}
