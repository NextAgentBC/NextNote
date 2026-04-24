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
        let epubs = enumerate(root)
        if epubs.isEmpty { return }

        let importer = EPUBImporter(vault: vault, context: context)
        for url in epubs {
            do {
                _ = try await importer.registerExisting(epubURL: url)
            } catch {
                continue
            }
        }
    }

    private static func enumerate(_ root: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in enumerator
            where url.pathExtension.lowercased() == "epub" {
            out.append(url)
        }
        return out
    }
}
