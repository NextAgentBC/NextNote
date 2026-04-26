import Foundation
import SwiftData

// Walks the main vault + any user-added media roots, registering .epub
// files not yet in SwiftData. Dedupes on content hash inside
// EPUBImporter.registerExisting. Safe to call repeatedly.
@MainActor
enum BookLibrary {

    static func scan(
        vault: VaultStore,
        ebooksRoot: URL?,
        context: ModelContext
    ) async {
        guard let root = ebooksRoot else { return }
        let (epubs, pdfs) = enumerate(root)

        if !epubs.isEmpty {
            let importer = EPUBImporter(vault: vault, context: context)
            for url in epubs {
                do {
                    _ = try await importer.registerExisting(epubURL: url)
                } catch {
                    continue
                }
            }
        }

        if !pdfs.isEmpty {
            let importer = PDFImporter(vault: vault, context: context)
            for url in pdfs {
                do {
                    _ = try await importer.registerExisting(pdfURL: url)
                } catch {
                    continue
                }
            }
        }
    }

    private static func enumerate(_ root: URL) -> (epubs: [URL], pdfs: [URL]) {
        guard FileManager.default.fileExists(atPath: root.path) else { return ([], []) }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return ([], []) }
        var epubs: [URL] = []
        var pdfs: [URL] = []
        for case let url as URL in enumerator {
            switch url.pathExtension.lowercased() {
            case "epub": epubs.append(url)
            case "pdf":  pdfs.append(url)
            default:     continue
            }
        }
        return (epubs, pdfs)
    }
}
