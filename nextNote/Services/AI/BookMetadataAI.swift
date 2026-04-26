import Foundation

struct BookMetadataSuggestion: Codable {
    let title: String?
    let author: String?
    let summary: String?
}

enum BookMetadataAI {

    static func titleLooksJunk(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count < 4 { return true }
        // ebook_001, book_abc, file_123 style names
        if t.range(of: #"^(ebook|book|file|document)[\s_-]?\d"#,
                   options: [.regularExpression, .caseInsensitive]) != nil { return true }
        // All-caps title that isn't an acronym (> 6 chars all caps = likely junk or filename)
        if t.count > 6 && t == t.uppercased() && t.rangeOfCharacter(from: .letters) != nil { return true }
        // Has underscores (leaked filename: my_great_book)
        if t.contains("_") { return true }
        // Looks like a raw filename: ends in .epub / .pdf
        if t.lowercased().hasSuffix(".epub") || t.lowercased().hasSuffix(".pdf") { return true }
        // UUID-style or hex garbage
        if t.range(of: #"^[0-9a-f]{8}[-_]"#,
                   options: [.regularExpression, .caseInsensitive]) != nil { return true }
        return false
    }

    @MainActor
    static func suggest(
        book: Book,
        chapterText: String?,
        ai: AIService
    ) async throws -> BookMetadataSuggestion {
        let system = """
        You are a librarian. Given book metadata and optionally a first-chapter excerpt, \
        return the clean title, author, and a one-sentence summary. \
        Reply STRICTLY as JSON with keys: title, author, summary. \
        Do not include markdown fences, explanation, or any text outside the JSON object.
        """

        var parts: [String] = []
        parts.append("Filename: \(book.relativePath.split(separator: "/").last.map(String.init) ?? book.relativePath)")
        parts.append("Current title: \(book.title)")
        if let author = book.author, !author.isEmpty {
            parts.append("Current author: \(author)")
        }
        if let text = chapterText, !text.isEmpty {
            let excerpt = String(text.prefix(2000))
            parts.append("First chapter excerpt:\n\(excerpt)")
        }
        let prompt = parts.joined(separator: "\n")

        let raw: String
        do {
            raw = try await ai.complete(prompt: prompt, system: system)
        } catch {
            NSLog("[BookMetadataAI] AI call failed: \(error)")
            return BookMetadataSuggestion(title: nil, author: nil, summary: nil)
        }

        return parse(raw) ?? BookMetadataSuggestion(title: nil, author: nil, summary: nil)
    }

    private static func parse(_ raw: String) -> BookMetadataSuggestion? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip markdown fences
        if s.hasPrefix("```") {
            if let nl = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: nl)...])
            }
        }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find first JSON object
        guard let start = s.firstIndex(of: "{"),
              let jsonStr = extractFirstObject(from: s, start: start),
              let data = jsonStr.data(using: .utf8) else { return nil }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(BookMetadataSuggestion.self, from: data)
    }

    private static func extractFirstObject(from s: String, start: String.Index) -> String? {
        var depth = 0
        var idx = start
        while idx < s.endIndex {
            switch s[idx] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(s[start...idx]) }
            default: break
            }
            idx = s.index(after: idx)
        }
        return nil
    }
}
