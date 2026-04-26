import Foundation

enum FolderCategorizer {

    struct FolderSuggestion: Codable {
        let folder: String
        let isNew: Bool

        enum CodingKeys: String, CodingKey {
            case folder
            case isNew = "isNew"
        }
    }

    @MainActor
    static func suggestFolder(
        book: Book,
        existingFolders: [String],
        ai: AIService
    ) async throws -> String {
        let system = """
        You are a librarian organizing an ebook library. \
        Given a list of existing folders and a new book, choose the BEST existing folder \
        OR propose exactly ONE new folder name if none fit well. \
        Reply STRICTLY as JSON: {"folder": "<name>", "isNew": true|false}. \
        No markdown, no explanation, no text outside the JSON object.
        """

        var parts: [String] = []
        parts.append("Existing folders: \(existingFolders.isEmpty ? "(none yet)" : existingFolders.joined(separator: ", "))")
        parts.append("Book title: \(book.title)")
        if let author = book.author, !author.isEmpty {
            parts.append("Author: \(author)")
        }
        if let summary = book.aiSuggestion?.summary, !summary.isEmpty {
            parts.append("Summary: \(summary)")
        }
        let prompt = parts.joined(separator: "\n")

        let raw: String
        do {
            raw = try await ai.complete(prompt: prompt, system: system)
        } catch {
            NSLog("[FolderCategorizer] AI call failed for \"\(book.title)\": \(error)")
            return book.author.flatMap { $0.isEmpty ? nil : String($0.prefix(40)) } ?? "Uncategorized"
        }

        if let suggestion = parse(raw) {
            let cleaned = suggestion.folder.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "Uncategorized" : cleaned
        }
        return "Uncategorized"
    }

    @MainActor
    static func batchSuggest(
        books: [Book],
        existingFolders: [String],
        ai: AIService
    ) async throws -> [(book: Book, suggestedFolder: String)] {
        var results: [(book: Book, suggestedFolder: String)] = []
        var knownFolders = existingFolders

        for book in books {
            let folder = (try? await suggestFolder(book: book, existingFolders: knownFolders, ai: ai))
                ?? "Uncategorized"
            results.append((book: book, suggestedFolder: folder))
            if !knownFolders.contains(folder) {
                knownFolders.append(folder)
            }
        }
        return results
    }

    private static func parse(_ raw: String) -> FolderSuggestion? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let nl = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: nl)...])
            }
        }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let start = s.firstIndex(of: "{"),
              let jsonStr = extractFirstObject(from: s, start: start),
              let data = jsonStr.data(using: .utf8) else { return nil }

        return try? JSONDecoder().decode(FolderSuggestion.self, from: data)
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
