import Foundation

// Persist the user-chosen vault URL as a security-scoped bookmark so we
// keep sandbox access across app launches. Blob is opaque and fine to
// store in UserDefaults; the URL itself may include paths we shouldn't
// leak, but UserDefaults is local-only.
enum VaultBookmark {
    private static let defaultsKey = "vaultBookmark"

    static func save(_ url: URL) throws {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func resolve() throws -> URL? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale {
            // Refresh with a new bookmark so next launch doesn't re-fail.
            try? save(url)
        }
        return url
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
