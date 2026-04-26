import SwiftUI
import SwiftData

enum FileImportRouter {
    @MainActor
    static func importFiles(urls: [URL], vault: VaultStore, appState: AppState, modelContext: ModelContext) {
        let epubs = urls.filter { $0.pathExtension.lowercased() == "epub" }
        let pdfs  = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        let rest  = urls.filter { ext in
            let e = ext.pathExtension.lowercased()
            return e != "epub" && e != "pdf"
        }

        if !epubs.isEmpty {
            Task { @MainActor in
                let importer = EPUBImporter(vault: vault, context: modelContext, aiService: appState.aiService)
                for url in epubs {
                    do {
                        _ = try await importer.importEPUB(from: url)
                    } catch {
                        appState.lastSaveError = "EPUB import failed: \(error.localizedDescription)"
                    }
                }
            }
        }

        if !pdfs.isEmpty {
            Task { @MainActor in
                let importer = PDFImporter(vault: vault, context: modelContext, aiService: appState.aiService)
                for url in pdfs {
                    do {
                        _ = try await importer.registerExisting(pdfURL: url)
                    } catch {
                        appState.lastSaveError = "PDF import failed: \(error.localizedDescription)"
                    }
                }
            }
        }

        for url in rest {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let fileType = FileType.from(url: url)
            let title    = url.deletingPathExtension().lastPathComponent
            let doc      = TextDocument(title: title, content: content, fileType: fileType)
            modelContext.insert(doc)
            appState.openNewTab(document: doc)
        }
    }
}
