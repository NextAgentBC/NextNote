import Foundation
import SwiftData

/// Persists open tabs: SwiftData save + write any modified note buffers
/// to disk via NoteIO.
enum VaultSaveCoordinator {
    @MainActor
    static func saveAll(
        modelContext: ModelContext,
        appState: AppState,
        vault: VaultStore
    ) {
        try? modelContext.save()

        for (tabId, relativePath) in appState.vaultOpenPairs {
            guard
                let tab = appState.openTabs.first(where: { $0.id == tabId }),
                tab.isModified,
                let url = vault.url(for: relativePath),
                MediaKind.from(url: url) == nil,
                url.pathExtension.lowercased() != "nndraw",
                !VaultStore.imageExts.contains(url.pathExtension.lowercased())
            else { continue }
            do {
                try NoteIO.write(url: url, content: tab.document.content)
                if let idx = appState.openTabs.firstIndex(where: { $0.id == tabId }) {
                    appState.openTabs[idx].isModified = false
                }
            } catch {
                appState.lastSaveError = "Write failed for \(relativePath): \(error.localizedDescription)"
            }
        }
    }
}
