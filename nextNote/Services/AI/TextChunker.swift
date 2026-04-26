import Foundation

struct TextChunker {
    struct Chunk {
        let index: Int
        let content: String
        let tokenCount: Int
    }

    static func chunk(book: Book, chapterTexts: [String]) -> [Chunk] {
        // llama.cpp embedding servers commonly run with -c 2048 even when
        // the model itself supports 40k+. Cap chunks at ~1500 tokens
        // (~6000 chars) with 600-char overlap to stay safely under 2048
        // tokens per request regardless of server config.
        let windowSize = 6000
        let overlap = 600
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
