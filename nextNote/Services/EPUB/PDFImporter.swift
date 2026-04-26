import Foundation
import SwiftData
import CryptoKit
#if os(macOS)
import PDFKit
#endif

/// Mirror of EPUBImporter for PDF files. PDFs don't need an unzip step
/// (the file IS the renderable artifact), so we only persist a Book
/// record with metadata + outline-derived TOC + a synthetic spine where
/// each entry maps to one page index.
@MainActor
final class PDFImporter {
    private let vault: VaultStore
    private let context: ModelContext
    private let aiService: AIService?

    init(vault: VaultStore, context: ModelContext, aiService: AIService? = nil) {
        self.vault = vault
        self.context = context
        self.aiService = aiService
    }

    enum ImportError: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let m): return "Could not open PDF: \(m)"
            }
        }
    }

    /// Register a .pdf already on disk as a Book (kind = .pdf). Dedupes
    /// on content hash. Returns nil if a book with the same hash exists.
    @discardableResult
    func registerExisting(pdfURL: URL) async throws -> Book? {
        let hash = try Self.fileSHA256(url: pdfURL)
        let dup = FetchDescriptor<Book>(predicate: #Predicate { $0.contentHash == hash })
        if let _ = try? context.fetch(dup).first { return nil }

        #if os(macOS)
        guard let doc = PDFDocument(url: pdfURL) else {
            throw ImportError.unreadable(pdfURL.lastPathComponent)
        }
        let attrs = doc.documentAttributes ?? [:]
        let titleRaw = (attrs[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (titleRaw?.isEmpty == false ? titleRaw! : pdfURL.deletingPathExtension().lastPathComponent)
        let author = (attrs[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let pageCount = doc.pageCount

        let toc = Self.extractTOC(from: doc)
        let tocData = (try? JSONEncoder().encode(toc)) ?? Data("[]".utf8)
        let spine = (0..<pageCount).map { BookSpineEntry(href: "page:\($0)", mediaType: "application/pdf") }
        let spineData = (try? JSONEncoder().encode(spine)) ?? Data("[]".utf8)
        #else
        let title = pdfURL.deletingPathExtension().lastPathComponent
        let author: String? = nil
        let tocData = Data("[]".utf8)
        let spineData = Data("[]".utf8)
        #endif

        let relativePath: String = vault.relativePath(for: pdfURL) ?? pdfURL.path

        let book = Book(
            id: UUID(),
            relativePath: relativePath,
            title: title,
            author: author,
            publisher: nil,
            language: nil,
            coverRelativePath: nil,
            tocJSON: tocData,
            spineJSON: spineData,
            opfRelativePath: "",
            contentHash: hash,
            kind: .pdf
        )
        context.insert(book)
        try context.save()

        if BookMetadataAI.titleLooksJunk(book.title), let ai = aiService {
            #if os(macOS)
            var firstPageText: String? = nil
            if let pdfDoc = PDFDocument(url: pdfURL) {
                firstPageText = (0..<min(3, pdfDoc.pageCount)).compactMap {
                    pdfDoc.page(at: $0)?.string
                }.joined(separator: "\n")
            }
            #else
            let firstPageText: String? = nil
            #endif
            let capturedBook = book
            let capturedText = firstPageText
            Task { @MainActor in
                let suggestion = try? await BookMetadataAI.suggest(
                    book: capturedBook, chapterText: capturedText, ai: ai)
                guard let suggestion, suggestion.title != nil || suggestion.author != nil else { return }
                capturedBook.aiSuggestion = suggestion
                try? capturedBook.modelContext?.save()
            }
        }

        return book
    }

    // MARK: - TOC extraction

    #if os(macOS)
    /// Walk the PDF's outline tree (bookmarks) into BookTOCEntry. Each
    /// entry's `spineIndex` is the destination page index — TOC clicks
    /// in the reader's drawer become straight page jumps.
    static func extractTOC(from doc: PDFDocument) -> [BookTOCEntry] {
        guard let outline = doc.outlineRoot else { return [] }
        return walk(outline, doc: doc)
    }

    private static func walk(_ node: PDFOutline, doc: PDFDocument) -> [BookTOCEntry] {
        var out: [BookTOCEntry] = []
        for i in 0..<node.numberOfChildren {
            guard let child = node.child(at: i) else { continue }
            let label = child.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var pageIndex: Int? = nil
            if let dest = child.destination, let page = dest.page {
                let idx = doc.index(for: page)
                if idx >= 0 { pageIndex = idx }
            }
            let children = walk(child, doc: doc)
            out.append(BookTOCEntry(
                title: label.isEmpty ? "Untitled" : label,
                href: pageIndex.map { "page:\($0)" } ?? "",
                children: children,
                spineIndex: pageIndex,
                anchor: nil
            ))
        }
        return out
    }
    #endif

    // MARK: - Internal

    private static func fileSHA256(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let h = SHA256.hash(data: data)
        return h.compactMap { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
