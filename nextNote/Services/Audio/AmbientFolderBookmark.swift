import Foundation

/// Persists the user's chosen ambient (long-term) media folder as a
/// security-scoped bookmark. `restore()` reopens the scope on relaunch
/// so the library can keep walking that folder without re-prompting.
enum AmbientFolderBookmark {
    static let bookmarkKey = "mediaLibrary.ambientFolder.bookmark"
    static let promptedFlagKey = "mediaLibrary.hasPromptedAmbientFolder"

    static func save(_ url: URL) {
        let bm = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bm, forKey: bookmarkKey)
    }

    /// Resolve the saved bookmark. Returns the URL plus a flag telling the
    /// caller whether scoped access started successfully — the caller owns
    /// the scope and must release it on deinit.
    static func restore() -> (url: URL, scopeStarted: Bool)? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        let started = url.startAccessingSecurityScopedResource()
        return (url, started)
    }

    static var hasPrompted: Bool {
        UserDefaults.standard.bool(forKey: promptedFlagKey)
    }

    static func markPrompted() {
        UserDefaults.standard.set(true, forKey: promptedFlagKey)
    }
}
