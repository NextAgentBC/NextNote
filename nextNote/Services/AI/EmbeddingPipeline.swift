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

        let batchSize = 8
        var embeddedChunks: [(idx: Int, content: String, embedding: [Float], tokenCount: Int)] = []

        for batchStart in stride(from: 0, to: chunks.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, chunks.count)
            let batch = Array(chunks[batchStart..<batchEnd])
            let texts = batch.map { $0.content }

            var embeddings: [[Float]]
            do {
                embeddings = try await ai.embed(texts)
            } catch {
                NSLog("[Embed] '\(title)' batch %d-%d FIRST attempt failed: %@", batchStart, batchEnd, String(describing: error))
                do {
                    embeddings = try await ai.embed(texts)
                } catch {
                    NSLog("[Embed] '\(title)' batch %d-%d RETRY failed: %@", batchStart, batchEnd, String(describing: error))
                    throw error
                }
            }
            NSLog("[Embed] '\(title)' batch %d-%d: got %d vectors", batchStart, batchEnd, embeddings.count)

            for (i, chunk) in batch.enumerated() {
                guard i < embeddings.count else { continue }
                embeddedChunks.append((
                    idx: chunk.index,
                    content: chunk.content,
                    embedding: embeddings[i],
                    tokenCount: chunk.tokenCount
                ))
            }
        }

        do {
            try await store.insertChunks(documentID: documentID, chunks: embeddedChunks)
            NSLog("[Embed] '\(title)' inserted %d chunks", embeddedChunks.count)
        } catch {
            NSLog("[Embed] '\(title)' insertChunks FAILED: %@", String(describing: error))
            throw error
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
