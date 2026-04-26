import Foundation
import SwiftData

@MainActor
final class SemanticSearchService: ObservableObject {
    @Published var results: [SearchResult] = []
    @Published var isSearching = false

    private let ai: AIService
    private let store: VectorStore
    private var books: [Book] = []

    init(ai: AIService, store: VectorStore) {
        self.ai = ai
        self.store = store
    }

    func updateBookCache(_ books: [Book]) {
        self.books = books
    }

    func search(query: String, scope: ContentTypeFilter? = .epub) async throws {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            return
        }
        isSearching = true
        defer { isSearching = false }

        let embeddings = try await ai.embed([query])
        guard let queryEmbedding = embeddings.first else {
            results = []
            return
        }

        let matches = try await store.searchSimilar(queryEmbedding: queryEmbedding, k: 10, filter: scope)
        results = matches.map { match in
            let book = books.first { $0.documentID == match.chunk.documentID }
            return SearchResult(
                book: book,
                documentTitle: match.chunk.documentTitle ?? "Unknown",
                chunkContent: match.chunk.content,
                similarity: match.similarity,
                chunkIndex: match.chunk.chunkIndex,
                documentID: match.chunk.documentID
            )
        }
    }

    func findSimilar(book: Book) async throws {
        guard let docID = book.documentID else { return }
        isSearching = true
        defer { isSearching = false }

        // Use the first chunk's embedding as the query
        let matches = try await store.searchSimilar(
            queryEmbedding: [],
            k: 10
        )
        // For "find similar", embed the book title + author as proxy query
        let queryText = [book.title, book.author].compactMap { $0 }.joined(separator: " ")
        let embeddings = try await ai.embed([queryText])
        guard let queryEmbedding = embeddings.first else { return }

        let allMatches = try await store.searchSimilar(queryEmbedding: queryEmbedding, k: 11)
        results = allMatches
            .filter { $0.chunk.documentID != docID }
            .prefix(10)
            .map { match in
                let matchedBook = books.first { $0.documentID == match.chunk.documentID }
                return SearchResult(
                    book: matchedBook,
                    documentTitle: match.chunk.documentTitle ?? "Unknown",
                    chunkContent: match.chunk.content,
                    similarity: match.similarity,
                    chunkIndex: match.chunk.chunkIndex,
                    documentID: match.chunk.documentID
                )
            }
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let book: Book?
    let documentTitle: String
    let chunkContent: String
    let similarity: Float
    let chunkIndex: Int
    let documentID: UUID
}
