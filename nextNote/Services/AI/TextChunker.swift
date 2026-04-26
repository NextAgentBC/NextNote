import Foundation

struct TextChunker {
    struct Chunk {
        let index: Int
        let content: String
        let tokenCount: Int
    }

    static func chunk(book: Book, chapterTexts: [String]) -> [Chunk] {
        var out: [Chunk] = []
        var chunkIdx = 0
        for text in chapterTexts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 50 else { continue }
            let tokenCount = trimmed.count / 4
            // Each spine entry becomes one chunk if under ~120k chars (~30k tokens).
            // For oversize entries split into 120k-char windows with 10k overlap.
            if trimmed.count <= 120_000 {
                out.append(Chunk(index: chunkIdx, content: trimmed, tokenCount: tokenCount))
                chunkIdx += 1
            } else {
                let windowSize = 120_000
                let overlap = 10_000
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
        }
        return out
    }
}
