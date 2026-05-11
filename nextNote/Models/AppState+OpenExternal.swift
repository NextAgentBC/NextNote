import Foundation
import SwiftData
import CryptoKit

extension AppState {
    /// Routes a file URL passed in by Finder ("Open With NextNote", drag onto
    /// Dock icon, double-click when NextNote is the default handler) to the
    /// matching surface inside the app.
    ///
    /// - md / plain text / source code: open as a tab. If the file lives
    ///   inside the configured Notes vault we reuse the vault tab path so
    ///   edits persist in place; otherwise we open a transient in-memory
    ///   TextDocument (Save As required to persist edits).
    /// - pdf: register with the Book library (dedupes on content hash) and
    ///   open the Book tab so it lands in the PDF reader.
    /// - epub: same as pdf.
    /// - anything else: ignored.
    func openExternalFile(url: URL, vault: VaultStore, context: ModelContext) {
        // Sandboxed apps launched via "Open With" receive a transient
        // entitlement for the file; for security-scoped URLs (drag from
        // Finder while already running) startAccessingSecurityScopedResource
        // is needed before any read.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()

        switch ext {
        case "pdf":
            Task { await importAndOpenPDF(url: url, vault: vault, context: context) }
        case "epub":
            Task { await importAndOpenEPUB(url: url, vault: vault, context: context) }
        default:
            openTextLike(url: url, vault: vault)
        }
    }

    // MARK: - Text-like

    private func openTextLike(url: URL, vault: VaultStore) {
        let type = FileType.from(url: url)
        let title = url.deletingPathExtension().lastPathComponent

        if let rel = vault.relativePath(for: url) {
            openVaultFile(relativePath: rel) {
                let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return TextDocument(title: title, content: content, fileType: type)
            }
            return
        }

        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let doc = TextDocument(title: title, content: content, fileType: type)
        openNewTab(document: doc)
    }

    // MARK: - PDF / EPUB

    @MainActor
    private func importAndOpenPDF(url: URL, vault: VaultStore, context: ModelContext) async {
        let importer = PDFImporter(vault: vault, context: context)
        do {
            if let book = try await importer.registerExisting(pdfURL: url) {
                openBookTab(bookID: book.id, title: book.title)
                return
            }
            // Dup — find the existing Book by content hash and open it.
            if let book = try findBook(matching: url, in: context) {
                openBookTab(bookID: book.id, title: book.title)
            }
        } catch {
            NSLog("[openExternalFile] pdf import failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func importAndOpenEPUB(url: URL, vault: VaultStore, context: ModelContext) async {
        let importer = EPUBImporter(vault: vault, context: context)
        do {
            if let book = try await importer.registerExisting(epubURL: url) {
                openBookTab(bookID: book.id, title: book.title)
                return
            }
            if let book = try findBook(matching: url, in: context) {
                openBookTab(bookID: book.id, title: book.title)
            }
        } catch {
            NSLog("[openExternalFile] epub import failed: \(error.localizedDescription)")
        }
    }

    private func findBook(matching url: URL, in context: ModelContext) throws -> Book? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.contentHash == hash })
        return try context.fetch(descriptor).first
    }
}
