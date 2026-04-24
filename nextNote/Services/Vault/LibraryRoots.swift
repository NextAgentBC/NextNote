import Foundation
import AppKit

// Three independent, always-present library roots. Each owns its own
// security-scoped bookmark. First-launch: user sees a setup screen; pick
// per-category or accept defaults under ~/Documents/nextNote/.
@MainActor
final class LibraryRoots: ObservableObject {

    enum Kind: String, CaseIterable, Identifiable {
        /// Notes / Media / Ebooks are the three roots required on first-run;
        /// Assets is optional and can be adopted on demand (first time the
        /// user opens the Asset Library it auto-picks the default path if
        /// unset, so existing installs upgrade smoothly without a re-setup).
        case notes, media, ebooks, assets
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .notes:  return "Notes"
            case .media:  return "Media"
            case .ebooks: return "Ebooks"
            case .assets: return "Assets"
            }
        }
        var icon: String {
            switch self {
            case .notes:  return "note.text"
            case .media:  return "music.note"
            case .ebooks: return "books.vertical"
            case .assets: return "photo.stack"
            }
        }
        var defaultSubdir: String { displayName }
        var bookmarkKey: String {
            "libraryRoot_" + rawValue
        }
    }

    /// Roots that must be set for the app to consider itself configured —
    /// Assets is excluded so upgrades from 0.1.x don't force a re-setup.
    /// Also the list that `LibrarySetupView` iterates on first launch.
    static let requiredKinds: [Kind] = [.notes, .media, .ebooks]

    @Published private(set) var notesRoot: URL?
    @Published private(set) var mediaRoot: URL?
    @Published private(set) var ebooksRoot: URL?
    @Published private(set) var assetsRoot: URL?

    private var access: [Kind: URL] = [:]

    var isConfigured: Bool {
        Self.requiredKinds.allSatisfy { url(for: $0) != nil }
    }

    /// Canonical parent for default roots. Created on demand.
    static var defaultParent: URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        return docs.appendingPathComponent("nextNote", isDirectory: true)
    }

    func defaultURL(for kind: Kind) -> URL {
        Self.defaultParent.appendingPathComponent(kind.defaultSubdir, isDirectory: true)
    }

    func url(for kind: Kind) -> URL? {
        switch kind {
        case .notes:  return notesRoot
        case .media:  return mediaRoot
        case .ebooks: return ebooksRoot
        case .assets: return assetsRoot
        }
    }

    /// Return the Assets root, adopting the default path (`~/Documents/nextNote/Assets/`)
    /// on first access. Called lazily when the user opens the Asset Library —
    /// existing 0.1.x installs don't get a setup prompt because this fires
    /// only on demand.
    @discardableResult
    func ensureAssetsRoot() -> URL? {
        if let existing = assetsRoot { return existing }
        return useDefault(kind: .assets)
    }

    init() {
        resolveAll()
    }

    deinit {
        for url in access.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Resolve

    func resolveAll() {
        for kind in Kind.allCases {
            if let url = resolve(kind: kind) {
                if url.startAccessingSecurityScopedResource() {
                    access[kind] = url
                }
                assign(url: url, to: kind)
            }
        }
    }

    private func resolve(kind: Kind) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: kind.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale, let fresh = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(fresh, forKey: kind.bookmarkKey)
        }
        return url
    }

    // MARK: - Apply

    /// Pick a folder via NSOpenPanel for a given kind. Persists the
    /// bookmark + starts security-scoped access.
    @discardableResult
    func pick(kind: Kind) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder for \(kind.displayName)."
        if let existing = url(for: kind) {
            panel.directoryURL = existing.deletingLastPathComponent()
        }
        let response = await panel.beginSheet()
        guard response == .OK, let url = panel.url else { return nil }
        apply(kind: kind, url: url)
        return url
    }

    /// Use the default path under ~/Documents/nextNote/<Kind>. Creates the
    /// directory if missing.
    @discardableResult
    func useDefault(kind: Kind) -> URL? {
        let fm = FileManager.default
        let target = defaultURL(for: kind)
        do {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        apply(kind: kind, url: target)
        return target
    }

    /// Apply a chosen URL — save bookmark, start access, publish.
    private func apply(kind: Kind, url: URL) {
        if let prior = access[kind] {
            prior.stopAccessingSecurityScopedResource()
            access[kind] = nil
        }
        guard let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(data, forKey: kind.bookmarkKey)
        if url.startAccessingSecurityScopedResource() {
            access[kind] = url
        }
        assign(url: url, to: kind)
    }

    private func assign(url: URL?, to kind: Kind) {
        switch kind {
        case .notes:  notesRoot = url
        case .media:  mediaRoot = url
        case .ebooks: ebooksRoot = url
        case .assets: assetsRoot = url
        }
    }

    /// Forget a root entirely (rarely called — mostly for testing / reset).
    func clear(kind: Kind) {
        if let prior = access[kind] {
            prior.stopAccessingSecurityScopedResource()
            access[kind] = nil
        }
        UserDefaults.standard.removeObject(forKey: kind.bookmarkKey)
        assign(url: nil, to: kind)
    }

    // MARK: - Legacy migration

    /// If the old single-vault bookmark exists and the Notes root isn't set
    /// yet, inherit it so upgrades don't lose the user's folder.
    func migrateLegacyVaultBookmarkIfNeeded() {
        guard notesRoot == nil,
              let data = UserDefaults.standard.data(forKey: "vaultBookmark")
        else { return }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return }
        UserDefaults.standard.set(data, forKey: Kind.notes.bookmarkKey)
        if url.startAccessingSecurityScopedResource() {
            access[.notes] = url
        }
        notesRoot = url
    }
}

private extension NSOpenPanel {
    func beginSheet() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { cont in
            self.begin { cont.resume(returning: $0) }
        }
    }
}
