import Foundation
import SwiftData

/// Persists open tabs. Vault-backed tabs write their buffer to disk via
/// NoteIO; legacy flat-mode tabs persist via SwiftData. Both run on every
/// save trigger — vault mode might still have a legacy TextDocument hanging
/// around mid-transition.
enum VaultSaveCoordinator {
    @MainActor
    static func saveAll(
        modelContext: ModelContext,
        vaultMode: Bool,
        appState: AppState,
        vault: VaultStore
    ) {
        try? modelContext.save()

        guard vaultMode else { return }
        for (tabId, relativePath) in appState.vaultOpenPairs {
            guard
                let tab = appState.openTabs.first(where: { $0.id == tabId }),
                tab.isModified,
                let url = vault.url(for: relativePath),
                MediaKind.from(url: url) == nil,
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
