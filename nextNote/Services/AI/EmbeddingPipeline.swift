import Foundation
import SwiftData

@MainActor
final class EmbeddingPipeline: ObservableObject {
    private let ai: AIService
    let store: VectorStore

    init(ai: AIService, store: VectorStore) {
        self.ai = ai
        self.store = store
    }

    func embed(book: Book, chapterTexts: [String]) async throws {
        let title = book.title
        let chunks = TextChunker.chunk(book: book, chapterTexts: chapterTexts)
        NSLog("[Embed] '\(title)': %d chapters → %d chunks", chapterTexts.count, chunks.count)
        guard !chunks.isEmpty else {
            book.embeddingStatus = .embedded
            return
        }

        let bookSnapshot = BookSnapshot(book: book)
        let documentID = try await store.upsertDocument(snapshot: bookSnapshot)
        book.documentID = documentID
        NSLog("[Embed] '\(title)' doc id %@", documentID.uuidString)

        // Clear any partial chunks from previous run, then append per batch
        // so progress is visible incrementally and a crash mid-book keeps
        // already-embedded chunks rather than discarding everything.
        try await store.clearChunks(documentID: documentID)

        for (i, chunk) in chunks.enumerated() {
            let texts = [chunk.content]
            var embeddings: [[Float]]
            do {
                embeddings = try await ai.embed(texts)
            } catch {
                NSLog("[Embed] '\(title)' chunk %d FIRST failed: %@", i, String(describing: error))
                do {
                    embeddings = try await ai.embed(texts)
                } catch {
                    NSLog("[Embed] '\(title)' chunk %d RETRY failed: %@", i, String(describing: error))
                    throw error
                }
            }
            guard let vec = embeddings.first else {
                NSLog("[Embed] '\(title)' chunk %d: empty embeddings array", i)
                continue
            }

            do {
                try await store.appendChunk(
                    documentID: documentID,
                    idx: chunk.index,
                    content: chunk.content,
                    embedding: vec,
                    tokenCount: chunk.tokenCount
                )
            } catch {
                NSLog("[Embed] '\(title)' chunk %d appendChunk FAILED: %@", i, String(describing: error))
                throw error
            }

            if (i + 1) % 5 == 0 || i == chunks.count - 1 {
                NSLog("[Embed] '\(title)': %d/%d chunks committed", i + 1, chunks.count)
            }
        }

        book.embeddingStatus = .embedded
    }

    func embedLibrary(books: [Book], chapterTextsProvider: ((@MainActor (Book) async -> [String]))?, progress: ((Double) -> Void)?) async throws {
        let pending = books.filter { $0.embeddingStatus != .embedded }
        let total = pending.count
        guard total > 0 else { return }

        for (idx, book) in pending.enumerated() {
            let texts = await chapterTextsProvider?(book) ?? []
            do {
                try await embed(book: book, chapterTexts: texts)
            } catch {
                book.embeddingStatus = .failed
            }
            progress?(Double(idx + 1) / Double(total))
        }
    }

    func retryPending(books: [Book], chapterTextsProvider: @MainActor (Book) async -> [String]) async {
        let pendingBooks = books.filter { $0.embeddingStatus == .pending || $0.embeddingStatus == .failed }
        for book in pendingBooks {
            let texts = await chapterTextsProvider(book)
            do {
                try await embed(book: book, chapterTexts: texts)
            } catch {
                book.embeddingStatus = .failed
            }
        }
    }
}

/// Value-type snapshot of Book fields needed by VectorStore — safe to send across actor boundaries.
struct BookSnapshot: Sendable {
    let contentHash: String
    let title: String
    let author: String?
    let relativePath: String
    let contentType: String

    init(book: Book) {
        self.contentHash = book.contentHash
        self.title = book.title
        self.author = book.author
        self.relativePath = book.relativePath
        self.contentType = book.kind == .pdf ? "pdf" : "epub"
    }
}
