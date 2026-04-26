import Foundation
import SwiftData
import CryptoKit

// Orchestrates: copy .epub into vault → unzip to Caches → parse → insert Book.
// Chapter export to markdown lives here too so the Book ←→ markdown round-trip
// has one owner.
@MainActor
final class EPUBImporter {

    enum ImportError: LocalizedError {
        case noVault
        case copyFailed(String)
        case alreadyImported(Book)

        var errorDescription: String? {
            switch self {
            case .noVault:                return "Choose a vault folder before importing EPUBs."
            case .copyFailed(let msg):    return "Failed to copy EPUB into vault: \(msg)"
            case .alreadyImported(let b): return "\"\(b.title)\" is already in your library."
            }
        }
    }

    private let vault: VaultStore
    private let context: ModelContext
    let aiService: AIService?
    let embeddingPipeline: EmbeddingPipeline?

    init(vault: VaultStore, context: ModelContext, aiService: AIService? = nil, embeddingPipeline: EmbeddingPipeline? = nil) {
        self.vault = vault
        self.context = context
        self.aiService = aiService
        self.embeddingPipeline = embeddingPipeline
    }

    // MARK: - Caches dir

    /// Per-book unzip workspace. Regenerated lazily if missing.
    static func unzipDir(for bookID: UUID) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches
            .appendingPathComponent("nextNote/Books", isDirectory: true)
            .appendingPathComponent(bookID.uuidString, isDirectory: true)
    }

    /// Re-parse the book's TOC + spine from its unzipped EPUB and persist
    /// back to SwiftData. Used to recover from cases where the original
    /// import landed an empty TOC (parser miss, import-time race) — the
    /// sidebar shows a generic "Chapter N" list as a fallback when
    /// `tocJSON` decodes to empty, so calling this and re-rendering
    /// surfaces the real chapter titles.
    @discardableResult
    static func refreshMetadata(_ book: Book, vault: VaultStore) -> Bool {
        do {
            let root = try ensureUnzipped(book, vault: vault)
            let parsed = try EPUBParser.parse(unzippedRoot: root)
            let tocEntries = parsed.toc.map { Self.convertToBookTOC($0) }
            let spineEntries = parsed.spine.map {
                BookSpineEntry(href: $0.href, mediaType: $0.mediaType)
            }
            let tocData = (try? JSONEncoder().encode(tocEntries)) ?? Data("[]".utf8)
            let spineData = (try? JSONEncoder().encode(spineEntries)) ?? Data("[]".utf8)
            book.tocJSON = tocData
            book.spineJSON = spineData
            return !tocEntries.isEmpty
        } catch {
            return false
        }
    }

    /// Ensure the book's unzipped workspace exists on disk. Used by the reader
    /// on open — the Caches dir can be wiped by the OS at any time.
    static func ensureUnzipped(_ book: Book, vault: VaultStore) throws -> URL {
        let dest = unzipDir(for: book.id)
        let opfFile = dest.appendingPathComponent(book.opfRelativePath)
        if FileManager.default.fileExists(atPath: opfFile.path) {
            return dest
        }
        guard let epubURL = resolveFileURL(book.relativePath, vault: vault) else {
            throw ImportError.copyFailed("path missing")
        }
        try EPUBParser.unzip(epubURL: epubURL, to: dest)
        return dest
    }

    /// Resolve a Book-stored path. Absolute (prefix "/") → direct URL;
    /// otherwise treated as vault-relative.
    static func resolveFileURL(_ path: String, vault: VaultStore) -> URL? {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return vault.url(for: path)
    }

    // MARK: - Import

    func importEPUB(from sourceURL: URL) async throws -> Book {
        guard let root = vault.root else { throw ImportError.noVault }

        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }

        // Unzip to a scratch dir first so we can read metadata and pick a slug.
        let scratchID = UUID()
        let scratchDir = Self.unzipDir(for: scratchID)
        try EPUBParser.unzip(epubURL: sourceURL, to: scratchDir)
        let parsed = try EPUBParser.parse(unzippedRoot: scratchDir)

        let hash = try fileSHA256(url: sourceURL)

        // De-dupe by content hash.
        let dupDescriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        if let existing = try? context.fetch(dupDescriptor).first {
            // Remove scratch — existing unzip dir stays.
            try? FileManager.default.removeItem(at: scratchDir)
            throw ImportError.alreadyImported(existing)
        }

        // Place the .epub + cover in <vault>/Books/<slug>/.
        let slug = makeSlug(title: parsed.metadata.title, hashPrefix: String(hash.prefix(6)))
        let bookDir = root
            .appendingPathComponent("Books", isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
        try FileManager.default.createDirectory(at: bookDir, withIntermediateDirectories: true)

        let fileName = sourceURL.lastPathComponent
        let epubDest = bookDir.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: epubDest.path) {
            try FileManager.default.removeItem(at: epubDest)
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: epubDest)
        } catch {
            throw ImportError.copyFailed(error.localizedDescription)
        }

        var coverRel: String? = nil
        if let cover = parsed.coverAbsoluteURL,
           FileManager.default.fileExists(atPath: cover.path) {
            let ext = cover.pathExtension.isEmpty ? "jpg" : cover.pathExtension
            let coverDest = bookDir.appendingPathComponent("cover.\(ext)")
            try? FileManager.default.removeItem(at: coverDest)
            try? FileManager.default.copyItem(at: cover, to: coverDest)
            coverRel = vault.relativePath(for: coverDest)
        }

        // Move scratch unzip to final book id location.
        let bookID = UUID()
        let finalUnzip = Self.unzipDir(for: bookID)
        try? FileManager.default.removeItem(at: finalUnzip)
        try FileManager.default.createDirectory(
            at: finalUnzip.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: scratchDir, to: finalUnzip)

        // Serialize TOC + spine.
        let tocEntries = parsed.toc.map { Self.convertToBookTOC($0) }
        let spineEntries = parsed.spine.map {
            BookSpineEntry(href: $0.href, mediaType: $0.mediaType)
        }
        let tocData = (try? JSONEncoder().encode(tocEntries)) ?? Data("[]".utf8)
        let spineData = (try? JSONEncoder().encode(spineEntries)) ?? Data("[]".utf8)

        let relativePath = vault.relativePath(for: epubDest) ?? "Books/\(slug)/\(fileName)"

        let book = Book(
            id: bookID,
            relativePath: relativePath,
            title: parsed.metadata.title,
            author: parsed.metadata.author,
            publisher: parsed.metadata.publisher,
            language: parsed.metadata.language,
            coverRelativePath: coverRel,
            tocJSON: tocData,
            spineJSON: spineData,
            opfRelativePath: parsed.opfRelativePath,
            contentHash: hash
        )
        context.insert(book)
        try context.save()

        await vault.scan()

        if BookMetadataAI.titleLooksJunk(book.title), let ai = aiService {
            let capturedBook = book
            let capturedVault = vault
            Task { @MainActor in
                let chapterText = await Self.firstChapterText(book: capturedBook, vault: capturedVault)
                let suggestion = try? await BookMetadataAI.suggest(
                    book: capturedBook, chapterText: chapterText, ai: ai)
                guard let suggestion, suggestion.title != nil || suggestion.author != nil else { return }
                capturedBook.aiSuggestion = suggestion
                try? capturedBook.modelContext?.save()
            }
        }

        if let pipeline = embeddingPipeline {
            let capturedBook = book
            let capturedVault = vault
            Task { @MainActor in
                let chapterTexts = await Self.allChapterTexts(book: capturedBook, vault: capturedVault)
                do {
                    try await pipeline.embed(book: capturedBook, chapterTexts: chapterTexts)
                    try? capturedBook.modelContext?.save()
                } catch {
                    capturedBook.embeddingStatus = .pending
                }
            }
        }

        return book
    }

    // MARK: - Markdown export

    /// Export every chapter as a markdown file under `<vault>/Books/<slug>/chapters/`.
    /// Returns the written URLs.
    @discardableResult
    func exportChaptersAsMarkdown(_ book: Book) async throws -> [URL] {
        let unzipRoot = try Self.ensureUnzipped(book, vault: vault)
        let contentBase = unzipRoot.appendingPathComponent(
            (book.opfRelativePath as NSString).deletingLastPathComponent,
            isDirectory: true
        )
        let spine: [BookSpineEntry] = (try? JSONDecoder().decode(
            [BookSpineEntry].self, from: book.spineJSON
        )) ?? []
        guard !spine.isEmpty else { return [] }

        guard let vaultRoot = vault.root else { throw ImportError.noVault }
        let bookDir = vaultRoot.appendingPathComponent(
            (book.relativePath as NSString).deletingLastPathComponent,
            isDirectory: true
        )
        let chaptersDir = bookDir.appendingPathComponent("chapters", isDirectory: true)
        try FileManager.default.createDirectory(at: chaptersDir, withIntermediateDirectories: true)

        var written: [URL] = []
        for (i, entry) in spine.enumerated() {
            let chapterURL = contentBase.appendingPathComponent(entry.href)
            guard let data = try? Data(contentsOf: chapterURL),
                  let xhtml = String(data: data, encoding: .utf8)
            else { continue }
            let md: String
            do {
                md = try XHTMLToMarkdown.convert(xhtml: xhtml)
            } catch { continue }

            let idx = String(format: "%03d", i + 1)
            let titleSlug = NoteIO.sanitize(
                (chapterURL.deletingPathExtension().lastPathComponent as NSString).lastPathComponent
            )
            let outName = "\(idx)-\(titleSlug).md"
            let outURL = chaptersDir.appendingPathComponent(outName)
            try NoteIO.write(url: outURL, content: md)
            written.append(outURL)
        }

        await vault.scan()
        return written
    }

    // MARK: - Helpers

    // MARK: - Register existing

    /// Register a .epub that already lives in the vault (on-disk) as a Book
    /// without copying. De-dupes on content hash. Returns the new Book, or
    /// nil if one with the same hash already exists.
    @discardableResult
    func registerExisting(epubURL: URL) async throws -> Book? {
        let hash = try fileSHA256(url: epubURL)
        let dupDescriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        if let _ = try? context.fetch(dupDescriptor).first { return nil }

        let bookID = UUID()
        let unzipDest = Self.unzipDir(for: bookID)
        try EPUBParser.unzip(epubURL: epubURL, to: unzipDest)
        let parsed = try EPUBParser.parse(unzippedRoot: unzipDest)

        // Path is vault-relative when inside vault; otherwise absolute (prefix "/").
        let relativePath: String = vault.relativePath(for: epubURL) ?? epubURL.path

        var coverRel: String? = nil
        if let cover = parsed.coverAbsoluteURL,
           FileManager.default.fileExists(atPath: cover.path) {
            let ext = cover.pathExtension.isEmpty ? "jpg" : cover.pathExtension
            let coverDest = epubURL.deletingLastPathComponent()
                .appendingPathComponent("cover.\(ext)")
            if !FileManager.default.fileExists(atPath: coverDest.path) {
                try? FileManager.default.copyItem(at: cover, to: coverDest)
            }
            coverRel = vault.relativePath(for: coverDest) ?? coverDest.path
        }

        let tocEntries = parsed.toc.map { Self.convertToBookTOC($0) }
        let spineEntries = parsed.spine.map {
            BookSpineEntry(href: $0.href, mediaType: $0.mediaType)
        }
        let tocData = (try? JSONEncoder().encode(tocEntries)) ?? Data("[]".utf8)
        let spineData = (try? JSONEncoder().encode(spineEntries)) ?? Data("[]".utf8)

        let book = Book(
            id: bookID,
            relativePath: relativePath,
            title: parsed.metadata.title,
            author: parsed.metadata.author,
            publisher: parsed.metadata.publisher,
            language: parsed.metadata.language,
            coverRelativePath: coverRel,
            tocJSON: tocData,
            spineJSON: spineData,
            opfRelativePath: parsed.opfRelativePath,
            contentHash: hash
        )
        context.insert(book)
        try context.save()
        return book
    }

    // MARK: - AI helpers

    static func allChapterTexts(book: Book, vault: VaultStore) async -> [String] {
        guard let root = try? ensureUnzipped(book, vault: vault) else { return [] }
        let spine: [BookSpineEntry] = (try? JSONDecoder().decode(
            [BookSpineEntry].self, from: book.spineJSON)) ?? []
        let contentBase = root.appendingPathComponent(
            (book.opfRelativePath as NSString).deletingLastPathComponent, isDirectory: true)
        var texts: [String] = []
        for entry in spine {
            let url = contentBase.appendingPathComponent(entry.href)
            guard let data = try? Data(contentsOf: url),
                  let xhtml = String(data: data, encoding: .utf8),
                  let md = try? XHTMLToMarkdown.convert(xhtml: xhtml),
                  !md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            texts.append(md)
        }
        return texts
    }

    static func firstChapterText(book: Book, vault: VaultStore) async -> String? {
        guard let root = try? ensureUnzipped(book, vault: vault) else { return nil }
        let spine: [BookSpineEntry] = (try? JSONDecoder().decode(
            [BookSpineEntry].self, from: book.spineJSON)) ?? []
        let contentBase = root.appendingPathComponent(
            (book.opfRelativePath as NSString).deletingLastPathComponent, isDirectory: true)
        for entry in spine.prefix(3) {
            let url = contentBase.appendingPathComponent(entry.href)
            guard let data = try? Data(contentsOf: url),
                  let xhtml = String(data: data, encoding: .utf8),
                  let md = try? XHTMLToMarkdown.convert(xhtml: xhtml),
                  !md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            return md
        }
        return nil
    }

    private static func convertToBookTOC(_ n: EPUBTOCNode) -> BookTOCEntry {
        BookTOCEntry(
            title: n.title,
            href: n.href,
            children: n.children.map { Self.convertToBookTOC($0) },
            spineIndex: n.spineIndex,
            anchor: n.anchor
        )
    }

    private func makeSlug(title: String, hashPrefix: String) -> String {
        let raw = NoteIO.sanitize(title).replacingOccurrences(of: " ", with: "-")
        let lower = raw.lowercased()
        let trimmed = String(lower.prefix(40))
        return trimmed.isEmpty ? "book-\(hashPrefix)" : "\(trimmed)-\(hashPrefix)"
    }

    private func fileSHA256(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 16) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
