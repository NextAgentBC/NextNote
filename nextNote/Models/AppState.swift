import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    // MARK: - AI
    let aiService: AIService = AIService()

    // MARK: - Vector DB
    let vectorStore: VectorStore = {
        let dsn = VectorDBSettings.shared.dsn
        return VectorStore(dsn: dsn)
    }()

    lazy var embeddingPipeline: EmbeddingPipeline = {
        EmbeddingPipeline(ai: aiService, store: vectorStore)
    }()

    lazy var semanticSearch: SemanticSearchService = {
        SemanticSearchService(ai: aiService, store: vectorStore)
    }()

    // MARK: - Tab Management
    @Published var openTabs: [TabItem] = []
    @Published var activeTabId: UUID?

    // MARK: - Snippet Insert (bridge between MarkdownToolbar and the native editor)
    @Published var pendingSnippet: SnippetInsert? = nil

    // MARK: - UI State
    @Published var showFileImporter: Bool = false
    @Published var showFileManager: Bool = true
    @Published var showSearchBar: Bool = false
    @Published var showMarkdownPreview: Bool = false
    @Published var isFocusMode: Bool = false
    @Published var previewMode: PreviewMode = .editor
    @Published var showMediaLibrary: Bool = false
    @Published var showYouTubeDownload: Bool = false
    @Published var showDownloadHistory: Bool = false
    @Published var showAssetLibrary: Bool = false
    @Published var showTerminal: Bool = UserDefaults.standard.bool(forKey: "nextnote.terminal.show") {
        didSet { UserDefaults.standard.set(showTerminal, forKey: "nextnote.terminal.show") }
    }
    /// Command injected into the embedded terminal by the palette or other
    /// surfaces. TerminalPane consumes the value and clears it.
    @Published var pendingTerminalCommand: String? = nil
    /// Shortcut cheatsheet overlay — ⌘/ toggles.
    @Published var showShortcuts: Bool = false
    /// Floating AI chat ball — ⌘⇧K toggles.
    @Published var showChatBall: Bool = false
    /// One-shot toggle for the floating markdown-preview window. ContentView
    /// observes this and calls `PreviewWindowController.shared.show(...)`
    /// (or `.close()`) — the actual window lives outside the SwiftUI scene
    /// so it can be screen-shared independently and pinned above other apps.
    @Published var triggerFloatingPreviewToggle: Bool = false
    /// Active book — derived from the active tab's `bookID`. Kept as a
    /// convenience @Published so non-tab surfaces (sidebar highlights) don't
    /// have to poke into openTabs.
    var activeBookID: UUID? {
        get { activeTab?.bookID }
        set {
            // Legacy setter: activates the first tab whose bookID matches.
            if let newValue,
               let tab = openTabs.first(where: { $0.bookID == newValue }) {
                activeTabId = tab.id
            }
        }
    }
    /// Anchor (XHTML id) to scroll to after the active book's chapter renders.
    /// Consumed by the reader webview after applying.
    @Published var pendingBookAnchor: String? = nil
    /// One-shot trigger from View > Rescan Library.
    @Published var triggerRescanLibrary: Bool = false

    /// One-shot trigger from File > Export > PDF…
    @Published var triggerExportPDF: Bool = false

    /// One-shot Media-menu triggers — the Media Library sheet observes
    /// these and runs the matching action when it becomes visible.
    @Published var triggerRestoreTitles: Bool = false
    @Published var triggerOrganizeLibrary: Bool = false
    @Published var triggerRescanMedia: Bool = false

    /// Reconcile / dedupe library sheet — toggled from Media menu or the
    /// Media Library sheet's toolbar.
    @Published var showReconcileLibrary: Bool = false

    // MARK: - Save trigger
    // Set to true by Cmd+S / menu; ContentView observes, calls modelContext.save(), resets to false.
    @Published var triggerSave: Bool = false

    // Surface disk-write errors (vault mode) to any view that wants to show them.
    @Published var lastSaveError: String?

    // MARK: - Search
    @Published var searchText: String = ""
    @Published var replaceText: String = ""
    @Published var searchOptions: SearchOptions = SearchOptions()

    // MARK: - Vault-opened tabs (R1)
    // Map vault-relative path → tab id so repeated clicks on the same tree
    // node activate the existing tab instead of spawning a new one.
    // R2 replaces TextDocument with a disk-backed Note and this map moves
    // onto TabItem directly via a `sourcePath` field.
    private var vaultTabByPath: [String: UUID] = [:]

    /// Sidebar selection. Directory-typed selections drive "new note here" /
    /// "new folder here" targets; file-typed selections are informational.
    @Published var selectedSidebarPath: String = ""  // "" = vault root

    /// Reverse map — tab id → vault relative path. Used by the save hooks
    /// in ContentView to write the tab's buffer back to the on-disk .md.
    func vaultPath(forTabId id: UUID) -> String? {
        vaultTabByPath.first(where: { $0.value == id })?.key
    }

    /// Every (tabId, relativePath) pair currently open. Save loop iterates
    /// this on Cmd+S / auto-save / scene-inactive.
    var vaultOpenPairs: [(UUID, String)] {
        vaultTabByPath.map { ($0.value, $0.key) }
    }

    var activeTab: TabItem? {
        openTabs.first { $0.id == activeTabId }
    }

    var activeTabIndex: Int? {
        openTabs.firstIndex { $0.id == activeTabId }
    }

    // MARK: - Tab Operations

    func openNewTab(document: TextDocument? = nil) {
        let tab: TabItem
        if let doc = document {
            // Check if already open
            if let existing = openTabs.first(where: { $0.document.id == doc.id }) {
                activeTabId = existing.id
                return
            }
            tab = TabItem(document: doc)
        } else {
            let newDoc = TextDocument()
            tab = TabItem(document: newDoc)
        }
        openTabs.append(tab)
        activeTabId = tab.id
    }

    /// Open (or activate) a tab for the given EPUB book. Dedupes by bookID.
    func openBookTab(bookID: UUID, title: String) {
        if let existing = openTabs.first(where: { $0.bookID == bookID }) {
            activeTabId = existing.id
            return
        }
        let tab = TabItem(bookID: bookID, title: title)
        openTabs.append(tab)
        activeTabId = tab.id
    }

    /// Open an asset or media file that lives outside the Notes vault in the
    /// main content area. Used by the sidebar Assets tray so preview/trim
    /// stays in-window instead of bouncing through a separate library sheet.
    func openExternalMedia(url: URL, title: String) {
        if let existing = openTabs.first(where: { $0.externalMediaURL == url }) {
            activeTabId = existing.id
            return
        }
        let doc = TextDocument(title: title, content: "", fileType: .md)
        var tab = TabItem(document: doc)
        tab.externalMediaURL = url
        openTabs.append(tab)
        activeTabId = tab.id
    }

    /// Open a vault-backed file as a tab. Dedupes by relative path so repeated
    /// sidebar clicks activate the existing tab. `makeDocument` is only called
    /// when no tab is open for that path yet.
    func openVaultFile(relativePath: String, makeDocument: () -> TextDocument) {
        if let existingId = vaultTabByPath[relativePath],
           openTabs.contains(where: { $0.id == existingId }) {
            activeTabId = existingId
            return
        }
        let tab = TabItem(document: makeDocument())
        openTabs.append(tab)
        activeTabId = tab.id
        vaultTabByPath[relativePath] = tab.id
    }

    func closeTab(id: UUID) {
        guard let index = openTabs.firstIndex(where: { $0.id == id }) else { return }
        openTabs.remove(at: index)
        vaultTabByPath = vaultTabByPath.filter { $0.value != id }

        if activeTabId == id {
            if openTabs.isEmpty {
                activeTabId = nil
            } else {
                let newIndex = min(index, openTabs.count - 1)
                activeTabId = openTabs[newIndex].id
            }
        }
    }

    func closeOtherTabs(except id: UUID) {
        openTabs.removeAll { $0.id != id }
        vaultTabByPath = vaultTabByPath.filter { $0.value == id }
        activeTabId = id
    }

    func closeBookTabs(bookID: UUID) {
        let ids = openTabs.compactMap { $0.bookID == bookID ? $0.id : nil }
        for id in ids {
            closeTab(id: id)
        }
    }

    // MARK: - Vault path sync
    //
    // Called by the sidebar after a rename / move / delete lands on disk so
    // open tabs keep pointing at the right file. All keys and prefixes are
    // vault-relative. Rename and move are the same op from the tab's view
    // (the path changed) — so there's one helper for both.

    /// Update tab mapping after `oldPath` became `newPath`. If the affected
    /// item is a directory, descendant paths get rewritten too.
    func vaultPathChanged(from oldPath: String, to newPath: String, isDirectory: Bool) {
        guard oldPath != newPath else { return }
        var updated: [String: UUID] = [:]
        for (path, tabId) in vaultTabByPath {
            if isDirectory {
                let prefix = oldPath.hasSuffix("/") ? oldPath : oldPath + "/"
                if path == oldPath || path.hasPrefix(prefix) {
                    let suffix = String(path.dropFirst(oldPath.count))
                    updated[newPath + suffix] = tabId
                } else {
                    updated[path] = tabId
                }
            } else {
                updated[path == oldPath ? newPath : path] = tabId
            }
        }
        vaultTabByPath = updated
    }

    /// Close any tabs that pointed at `deletedPath` (or children, if it was
    /// a directory).
    func vaultPathDeleted(_ deletedPath: String, isDirectory: Bool) {
        let idsToClose: [UUID] = vaultTabByPath.compactMap { (path, tabId) in
            if isDirectory {
                let prefix = deletedPath.hasSuffix("/") ? deletedPath : deletedPath + "/"
                return (path == deletedPath || path.hasPrefix(prefix)) ? tabId : nil
            } else {
                return path == deletedPath ? tabId : nil
            }
        }
        for id in idsToClose { closeTab(id: id) }
    }

    /// Register a path → tab mapping. Used when a newly-created vault file
    /// gets opened immediately after creation.
    func registerVaultPath(_ relativePath: String, for tabId: UUID) {
        vaultTabByPath[relativePath] = tabId
    }

    // MARK: - Search

    func toggleSearch() {
        showSearchBar.toggle()
        if !showSearchBar {
            searchText = ""
            replaceText = ""
        }
    }
}

// MARK: - Supporting Types

/// A pending snippet insert request: text to insert at the editor's current cursor,
/// with an optional cursor offset within the inserted text (e.g. place cursor inside **|**).
struct SnippetInsert: Equatable {
    let text: String
    let cursorOffset: Int  // characters from start of inserted text; 0 = before all text
}

struct TabItem: Identifiable {
    let id: UUID
    var document: TextDocument
    var isModified: Bool
    var cursorPosition: Int
    var scrollOffset: CGFloat
    /// When set, this tab is an EPUB reader tab — the TextDocument is a
    /// placeholder only. Views switch on this to pick EPUBReaderHost.
    var bookID: UUID?
    var bookTitle: String?
    /// File URL for media opened from outside the Notes vault, e.g. the
    /// Assets sidebar. The editor body routes this to MediaPlayerView or an
    /// image preview, and save hooks ignore it.
    var externalMediaURL: URL?

    init(document: TextDocument) {
        self.id = UUID()
        self.document = document
        self.isModified = false
        self.cursorPosition = 0
        self.scrollOffset = 0
        self.bookID = nil
        self.bookTitle = nil
        self.externalMediaURL = nil
    }

    init(bookID: UUID, title: String) {
        self.id = UUID()
        // Placeholder TextDocument so downstream code that expects one keeps
        // working; nothing writes to it in EPUB mode.
        self.document = TextDocument(title: title, content: "", fileType: .epub)
        self.isModified = false
        self.cursorPosition = 0
        self.scrollOffset = 0
        self.bookID = bookID
        self.bookTitle = title
        self.externalMediaURL = nil
    }
}

enum PreviewMode: String, CaseIterable {
    case editor = "Editor"
    case split = "Split"
    case preview = "Preview"

    var iconName: String {
        switch self {
        case .editor: return "doc.text"
        case .split: return "rectangle.split.2x1"
        case .preview: return "eye"
        }
    }
}

struct SearchOptions {
    var caseSensitive: Bool = false
    var wholeWord: Bool = false
    var useRegex: Bool = false
}
