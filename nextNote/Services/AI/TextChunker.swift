import Foundation

struct TextChunker {
    struct Chunk {
        let index: Int
        let content: String
        let tokenCount: Int
    }

    static func chunk(book: Book, chapterTexts: [String]) -> [Chunk] {
        // RAG best practice is ~1000-2000 tokens per chunk for retrieval
        // precision. 5000 chars ≈ 1250 tokens. At ~300 tok/s prefill that's
        // ~4s per chunk, much faster than larger windows for similar-or-better
        // search quality. 500-char overlap preserves context across boundaries.
        let windowSize = 5000
        let overlap = 500
        var out: [Chunk] = []
        var chunkIdx = 0
        for text in chapterTexts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 50 else { continue }
            if trimmed.count <= windowSize {
                out.append(Chunk(index: chunkIdx, content: trimmed, tokenCount: trimmed.count / 4))
                chunkIdx += 1
                continue
            }
            var start = trimmed.startIndex
            while start < trimmed.endIndex {
                let end = trimmed.index(start, offsetBy: windowSize, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
                let slice = String(trimmed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if slice.count >= 50 {
                    out.append(Chunk(index: chunkIdx, content: slice, tokenCount: slice.count / 4))
                    chunkIdx += 1
                }
                if end == trimmed.endIndex { break }
                start = trimmed.index(start, offsetBy: windowSize - overlap, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            }
        }
        return out
    }
}
