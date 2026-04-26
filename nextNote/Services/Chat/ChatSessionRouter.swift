import Foundation

enum ChatSessionRouter {
    static func sync(appState: AppState, vault: VaultStore, preferences: UserPreferences) {
        appState.activeChatSession?.saveNow()

        guard preferences.vaultMode,
              let root = vault.root,
              let tabId = appState.activeTabId,
              let relPath = appState.vaultPath(forTabId: tabId)
        else {
            appState.activeChatSession = nil
            return
        }

        if appState.activeChatSession?.relativePath == relPath {
            return
        }

        let transcript = ChatStore.load(relativePath: relPath, vaultRoot: root)
        appState.activeChatSession = ChatSession(
            relativePath: relPath,
            vaultRoot: root,
            messages: transcript?.messages ?? []
        )
    }
}
