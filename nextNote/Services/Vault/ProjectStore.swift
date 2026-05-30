import Foundation
import AppKit
import Combine

/// One project = one folder. Inside, `.nextnote/library.store` holds the
/// SwiftData library; `Media/`, `Ebooks/`, `Assets/` are convention
/// subdirectories the media + ebook + asset features write into.
///
/// ProjectStore is the single source of truth for which project is open,
/// the recents list, and the security-scoped bookmark for the current
/// folder. There is exactly one `current` at a time — switching projects
/// closes the previous one (the ModelContainer is rebuilt by App scene).
@MainActor
final class ProjectStore: ObservableObject {

    /// Subdirectory names the rest of the app relies on. Auto-created on
    /// project open if missing.
    enum Subdir: String, CaseIterable {
        case media   = "Media"
        case ebooks  = "Ebooks"
        case assets  = "Assets"
        case meta    = ".nextnote"
    }

    struct RecentEntry: Identifiable, Codable, Equatable {
        let id: UUID
        var name: String
        var bookmarkData: Data
        var lastOpenedAt: Date
        var pathHint: String     // last known path, shown in welcome list

        init(name: String, bookmarkData: Data, path: String, lastOpenedAt: Date = .now) {
            self.id = UUID()
            self.name = name
            self.bookmarkData = bookmarkData
            self.lastOpenedAt = lastOpenedAt
            self.pathHint = path
        }
    }

    @Published private(set) var current: URL?
    @Published private(set) var recents: [RecentEntry] = []

    private var accessing: URL?
    private let recentsFileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let nextNoteDir = appSupport.appendingPathComponent("NextNote", isDirectory: true)
        try? FileManager.default.createDirectory(at: nextNoteDir, withIntermediateDirectories: true)
        self.recentsFileURL = nextNoteDir.appendingPathComponent("recents.json")
        loadRecents()
        migrateLegacyRootsIfNeeded()
    }

    deinit {
        accessing?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Open / close / switch

    /// Open a folder as the current project. Persists a security-scoped
    /// bookmark in `recents.json`, starts access, creates the convention
    /// subdirectories, and bumps it to the top of the recents list.
    @discardableResult
    func open(url: URL) -> URL? {
        accessing?.stopAccessingSecurityScopedResource()
        accessing = nil
        guard url.startAccessingSecurityScopedResource() else { return nil }
        accessing = url

        ensureSubdirectories(under: url)

        current = url
        recordRecent(url: url)
        return url
    }

    /// Show an NSOpenPanel for the user to pick a project folder.
    @discardableResult
    func pick() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Project"
        panel.message = "Pick a folder to use as your nextNote project."
        let response = await panel.beginSheet()
        guard response == .OK, let url = panel.url else { return nil }
        return open(url: url)
    }

    /// Open a recent project by id. Resolves the stored bookmark; refreshes
    /// it if stale.
    @discardableResult
    func openRecent(_ entry: RecentEntry) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: entry.bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            removeRecent(id: entry.id)
            return nil
        }
        let opened = open(url: url)
        if stale, let opened, let fresh = try? opened.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            updateRecentBookmark(id: entry.id, data: fresh)
        }
        return opened
    }

    /// Close the current project. The App scene observes `current` and
    /// swaps the ContentView for the WelcomeView.
    func close() {
        accessing?.stopAccessingSecurityScopedResource()
        accessing = nil
        current = nil
    }

    func removeRecent(id: UUID) {
        recents.removeAll { $0.id == id }
        saveRecents()
    }

    // MARK: - Convention subdirs

    func subdir(_ kind: Subdir) -> URL? {
        guard let current else { return nil }
        return current.appendingPathComponent(kind.rawValue, isDirectory: true)
    }

    /// `<project>/.nextnote/library.store` — SwiftData persistence file.
    var storeURL: URL? {
        subdir(.meta)?.appendingPathComponent("library.store", isDirectory: false)
    }

    private func ensureSubdirectories(under url: URL) {
        let fm = FileManager.default
        for kind in Subdir.allCases {
            let sub = url.appendingPathComponent(kind.rawValue, isDirectory: true)
            try? fm.createDirectory(at: sub, withIntermediateDirectories: true)
        }
    }

    // MARK: - Recents persistence

    private func loadRecents() {
        guard let data = try? Data(contentsOf: recentsFileURL),
              let decoded = try? JSONDecoder().decode([RecentEntry].self, from: data) else {
            return
        }
        recents = decoded.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
    }

    private func saveRecents() {
        let sorted = recents.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        try? data.write(to: recentsFileURL, options: .atomic)
    }

    private func recordRecent(url: URL) {
        guard let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        let path = url.path(percentEncoded: false)
        if let idx = recents.firstIndex(where: { $0.pathHint == path }) {
            recents[idx].bookmarkData = data
            recents[idx].lastOpenedAt = .now
        } else {
            recents.insert(
                RecentEntry(name: url.lastPathComponent, bookmarkData: data, path: path),
                at: 0
            )
        }
        recents = recents.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
        saveRecents()
    }

    private func updateRecentBookmark(id: UUID, data: Data) {
        guard let idx = recents.firstIndex(where: { $0.id == id }) else { return }
        recents[idx].bookmarkData = data
        saveRecents()
    }

    // MARK: - One-shot migration from LibraryRoots era

    /// Pre-0.6 stored three separate security-scoped bookmarks
    /// (`libraryRoot_notes/_media/_ebooks/_assets`) plus a legacy
    /// `vaultBookmark`. The unified-root migration (0.5.x) made
    /// `libraryRoot_notes` point at the project parent. Inherit that as
    /// the initial project, add it to recents, then drop all the old keys.
    private func migrateLegacyRootsIfNeeded() {
        let ud = UserDefaults.standard
        let legacyKeys = [
            "libraryRoot_notes",
            "libraryRoot_media",
            "libraryRoot_ebooks",
            "libraryRoot_assets",
            "vaultBookmark",
            "nextnote.unifyRootDone",
        ]
        guard !ud.bool(forKey: "nextnote.projectStoreMigrated") else { return }

        let candidateKeys = ["libraryRoot_notes", "vaultBookmark"]
        var adopted: URL?
        for key in candidateKeys {
            guard let data = ud.data(forKey: key) else { continue }
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            adopted = url
            break
        }
        if let adopted, let data = try? adopted.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            let path = adopted.path(percentEncoded: false)
            recents.insert(
                RecentEntry(name: adopted.lastPathComponent, bookmarkData: data, path: path),
                at: 0
            )
            saveRecents()
        }
        for key in legacyKeys {
            ud.removeObject(forKey: key)
        }
        ud.set(true, forKey: "nextnote.projectStoreMigrated")
    }
}

private extension NSOpenPanel {
    func beginSheet() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { cont in
            self.begin { cont.resume(returning: $0) }
        }
    }
}
