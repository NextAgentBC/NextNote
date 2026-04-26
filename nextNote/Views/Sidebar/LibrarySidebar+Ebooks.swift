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
            if ebooksExpanded {
                ScrollView {
                    BooksSection(books: books)
                }
                .frame(maxHeight: 260)
            }
        }
    }
}
