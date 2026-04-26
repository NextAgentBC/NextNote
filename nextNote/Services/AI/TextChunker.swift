import Foundation

struct TextChunker {
    struct Chunk {
        let index: Int
        let content: String
        let tokenCount: Int
    }

    static func chunk(book: Book, chapterTexts: [String]) -> [Chunk] {
        // Server runs with -c 40960 -np 1 (single slot, full 40k ctx). Per-chunk
        // prefill on iGPU is ~210ms/token, so 2000 tokens ≈ 10s. Larger chunks
        // would push request time past the URLSession timeout for marginal
        // retrieval gain. 8000 chars = ~2000 tokens balances speed and
        // semantic coherence per chunk.
        let windowSize = 8000
        let overlap = 800
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
