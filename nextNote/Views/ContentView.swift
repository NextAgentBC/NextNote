import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var libraryRoots: LibraryRoots
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \TextDocument.modifiedAt, order: .reverse) private var documents: [TextDocument]
    @StateObject private var preferences = UserPreferences.shared
    @State private var showAIPanel = false
    @State private var showSettings = false
    @State private var showAmbientFolderPrompt = false

    var body: some View {
        Group {
            if preferences.vaultMode && !libraryRoots.isConfigured {
                LibrarySetupView()
                    .environmentObject(libraryRoots)
            } else if appState.isFocusMode {
                focusModeView
            } else {
                mainLayout
            }
        }
        // Bind VaultStore to the Notes root — the sole source of truth is
        // LibraryRoots; VaultStore just operates on whatever URL is active.
        .onAppear {
            libraryRoots.migrateLegacyVaultBookmarkIfNeeded()
            vault.adoptNotesRoot(libraryRoots.notesRoot)
        }
        .onReceive(libraryRoots.$notesRoot) { url in
            vault.adoptNotesRoot(url)
        }
        .onAppear {
            if !preferences.vaultMode, appState.openTabs.isEmpty {
                let defaultType = FileType(rawValue: preferences.defaultFileType) ?? .txt
                let doc = TextDocument(fileType: defaultType)
                modelContext.insert(doc)
                appState.openNewTab(document: doc)
            }
            if MediaLibrary.shared.shouldPromptForAmbientFolder {
                showAmbientFolderPrompt = true
            }
        }
        .alert("Set up your ambient library?", isPresented: $showAmbientFolderPrompt) {
            Button("Choose Folder…") {
                Task {
                    _ = await MediaLibrary.shared.pickAmbientFolder()
                }
            }
            Button("Skip", role: .cancel) {
                MediaLibrary.shared.markPrompted()
            }
        } message: {
            Text("Pick a long-term folder for your music and video collection. nextNote will auto-scan it and add everything to your media library. You can change it later from the Media menu.")
        }
        // Daily digest: fire on first launch of the day, in vault mode, when
        // the Gemini (or other remote) provider is configured. No-ops otherwise.
        .task {
            guard preferences.vaultMode else { return }
            await DailyDigestService.shared.generateIfDue()
        }
        // Library scan: rerun when any of the three roots change.
        .task(id: vault.root) { await rescanLibrary() }
        .onReceive(libraryRoots.$ebooksRoot) { _ in Task { await rescanLibrary() } }
        .onReceive(libraryRoots.$mediaRoot) { _ in Task { await rescanLibrary() } }
        .onChange(of: appState.triggerRescanLibrary) { _, v in
            if v {
                Task { await rescanLibrary() }
                appState.triggerRescanLibrary = false
            }
        }
        .onChange(of: appState.triggerOpenDailyNote) { _, v in
            if v {
                openDailyNote()
                appState.triggerOpenDailyNote = false
            }
        }
        .onChange(of: appState.triggerApplyPreset) { _, v in
            if v {
                applyPreset()
                appState.triggerApplyPreset = false
            }
        }
        // Rescan whenever the window regains focus — user dropped a file in
        // Finder, switches back, expects to see it instantly.
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await rescanLibrary() }
        }
        #endif
        // Cheap tick every 15s while app is frontmost — catches files added
        // while the window was already focused.
        .task(id: vault.root) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await rescanLibrary()
            }
        }
        // Auto-save: re-starts whenever autoSaveInterval changes; cancelled on view disappear.
        // interval == 0 means "manual only" — task returns immediately without looping.
        .task(id: preferences.autoSaveInterval) {
            let interval = preferences.autoSaveInterval
            guard interval > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                saveAll()
            }
        }
        // Cmd+S / manual save trigger from nextNoteCommands
        .onChange(of: appState.triggerSave) { _, triggered in
            guard triggered else { return }
            saveAll()
            appState.triggerSave = false
        }
        // Save whenever the scene goes inactive (Cmd+Tab / home button / app switch)
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                saveAll()
            }
        }
        // Per-note chat session: load the sidecar whenever the active tab
        // changes so the AI panel reflects *this* note's conversation.
        .onChange(of: appState.activeTabId) { _, _ in syncChatSession() }
        .onChange(of: vault.root) { _, _ in syncChatSession() }
        .onAppear { syncChatSession() }
        // Media library sheet — opened via AmbientBar button or Cmd+Shift+M.
        .sheet(isPresented: $appState.showMediaLibrary) {
            MediaLibraryView()
                .environmentObject(appState)
                .frame(minWidth: 760, minHeight: 460)
        }
        // YouTube download sheet — opened via Media menu.
        .sheet(isPresented: $appState.showYouTubeDownload) {
            YouTubeDownloadView()
        }
        // Asset Library sheet — grid browser for the fourth library root
        // (images / video / audio). Cells are draggable onto the markdown
        // editor, which turns the drop into `![](…)` syntax.
        .sheet(isPresented: $appState.showAssetLibrary) {
            AssetLibraryView()
                .environmentObject(appState)
                .environmentObject(libraryRoots)
        }
        // File importer: supports both toolbar button and macOS menu (via appState.showFileImporter)
        .fileImporter(
            isPresented: $appState.showFileImporter,
            allowedContentTypes: FileType.openableUTTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): importFiles(from: urls)
            case .failure: break
            }
        }
    }

    // MARK: - Save (vault-aware)
    //
    // Vault-backed tabs write their buffer to disk via NoteIO. Legacy flat-mode
    // tabs persist via SwiftData. Both run on every save trigger — vault mode
    // might still have a legacy TextDocument hanging around mid-transition.
    private func saveAll() {
        // Legacy SwiftData save (keeps flat-mode working + any AI caches persisted)
        try? modelContext.save()

        // Vault-backed: write each open tab's buffer to its .md on disk.
        // Media tabs reuse TextDocument as a placeholder carrier; writing
        // that carrier back to disk would corrupt the binary file, so skip.
        guard preferences.vaultMode else { return }
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

    // MARK: - File Import (MVP: copy content into SwiftData)

    @MainActor
    private func rescanLibrary() async {
        await BookLibrary.scan(
            vault: vault,
            ebooksRoot: libraryRoots.ebooksRoot,
            context: modelContext
        )
        await MediaLibrary.shared.scanRoot(libraryRoots.mediaRoot)
    }

    // MARK: - AI workflow (Phase C)

    @MainActor
    private func openDailyNote() {
        do {
            let resolved = try DailyNoteRouter.resolve(notesRoot: libraryRoots.notesRoot)
            appState.openVaultFile(relativePath: resolved.relativePath) {
                let content = (try? String(contentsOf: resolved.absoluteURL, encoding: .utf8)) ?? ""
                let title = ((resolved.relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
                return TextDocument(title: title, content: content, fileType: .md)
            }
            appState.selectedSidebarPath = resolved.relativePath
            if resolved.wasCreated {
                Task { await rescanLibrary() }   // new file — refresh sidebar tree
            }
        } catch {
            appState.lastSaveError = "Daily note: \(error.localizedDescription)"
        }
    }

    private func applyPreset() {
        guard let notesRoot = libraryRoots.notesRoot else {
            appState.lastSaveError = "Notes root is not configured."
            return
        }
        do {
            let report = try VaultPresetSeeder.seed(into: notesRoot)
            Task { await rescanLibrary() }
            // Surface the report via the save-error channel (a shared banner) —
            // not a real error, but the same UX lane reaches the user.
            let parts: [String] = [
                report.copied.isEmpty ? nil : "copied \(report.copied.count)",
                report.skipped.isEmpty ? nil : "kept \(report.skipped.count) identical",
                report.conflicts.isEmpty ? nil : "skipped \(report.conflicts.count) conflicting"
            ].compactMap { $0 }
            appState.lastSaveError = "AI Soul preset: " + (parts.isEmpty ? "already up to date." : parts.joined(separator: ", ") + ".")
        } catch {
            appState.lastSaveError = "Preset apply failed: \(error.localizedDescription)"
        }
    }

    private func importFiles(from urls: [URL]) {
        let epubs = urls.filter { $0.pathExtension.lowercased() == "epub" }
        let rest = urls.filter { $0.pathExtension.lowercased() != "epub" }

        if !epubs.isEmpty {
            Task { @MainActor in
                let importer = EPUBImporter(vault: vault, context: modelContext)
                for url in epubs {
                    do {
                        _ = try await importer.importEPUB(from: url)
                    } catch {
                        appState.lastSaveError = "EPUB import failed: \(error.localizedDescription)"
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

    // MARK: - Sidebar (vault tree vs legacy flat list, gated by vaultMode flag)

    @ViewBuilder
    private var sidebar: some View {
        if preferences.vaultMode {
            LibrarySidebar()
        } else {
            FileListView(documents: documents)
        }
    }

    // MARK: - Main Layout

    private var mainLayout: some View {
        #if os(macOS)
        NavigationSplitView {
            sidebar
                .frame(minWidth: 200)
        } detail: {
            editorArea
        }
        .toolbar { macToolbar }
        .overlay(alignment: .top) {
            if appState.showCommandPalette {
                CommandPalette()
                    .environmentObject(appState)
                    .environmentObject(libraryRoots)
                    .padding(.top, 80)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if appState.showCaptureHUD {
                CaptureHUD()
                    .environmentObject(appState)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: appState.showCommandPalette)
        .animation(.easeOut(duration: 0.15), value: appState.showCaptureHUD)
        #else
        NavigationStack {
            editorArea
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { iOSToolbar }
                .sheet(isPresented: $appState.showFileManager) {
                    NavigationStack {
                        FileListView(documents: documents)
                            .navigationTitle("Files")
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { appState.showFileManager = false }
                                }
                            }
                    }
                }
                .sheet(isPresented: $showAIPanel) {
                    NavigationStack {
                        AIActionPanelSheetView(isPresented: $showAIPanel)
                    }
                    .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $showSettings) {
                    NavigationStack {
                        SettingsView()
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { showSettings = false }
                                }
                            }
                    }
                }
        }
        #endif
    }

    // MARK: - Editor Area

    private var editorArea: some View {
        VStack(spacing: 0) {
            if appState.openTabs.count > 1 {
                TabBarView()
            }

            if appState.showSearchBar {
                SearchBarView()
            }

            // Markdown toolbar — only for real .md text tabs. EPUB book tabs
            // and media tabs use a placeholder TextDocument that shouldn't
            // trigger markdown editing affordances.
            if let tab = appState.activeTab,
               tab.bookID == nil,
               tab.document.fileType == .md,
               mediaURL(for: tab) == nil {
                MarkdownToolbarView { text, offset in
                    insertSnippet(text: text, cursorOffset: offset)
                }
            }

            editorAndDock

            #if os(macOS)
            if appState.showTerminal {
                Divider()
                TerminalPane(
                    workingDirectory: libraryRoots.notesRoot,
                    pendingCommand: $appState.pendingTerminalCommand
                )
                .frame(minHeight: 120, idealHeight: 220, maxHeight: 400)
            }
            #endif

            Divider()
            AmbientBar()

            StatusBarView()
        }
        .navigationTitle(activeContentTitle)
        #if os(macOS)
        .navigationSubtitle(activeContentSubtitle)
        #endif
    }

    /// What the macOS window chrome shows — active book / note / empty.
    private var activeContentTitle: String {
        if let tab = appState.activeTab {
            if let bt = tab.bookTitle, !bt.isEmpty { return bt }
            let t = tab.document.title
            if !t.isEmpty { return t }
        }
        return "nextNote"
    }

    /// Faint secondary text under the title — shows the current book's
    /// author, or the vault folder name when nothing is open.
    private var activeContentSubtitle: String {
        if let tab = appState.activeTab, let id = tab.bookID {
            let desc = FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })
            if let b = try? modelContext.fetch(desc).first, let a = b.author, !a.isEmpty {
                return a
            }
            return ""
        }
        return vault.root?.lastPathComponent ?? ""
    }

    /// The editor body, optionally with the AI dock split below it. On macOS
    /// we use VSplitView so the user can drag the divider; on iOS the AI
    /// panel stays as a sheet (driven by `showAIPanel` in mainLayout).
    @ViewBuilder
    private var editorAndDock: some View {
        #if os(macOS)
        if showAIPanel {
            VSplitView {
                editorBody
                    .frame(minHeight: 180)
                AIChatPanelView(isPresented: $showAIPanel)
                    .frame(minHeight: 220, idealHeight: 320)
            }
        } else {
            editorBody
        }
        #else
        editorBody
        #endif
    }

    @ViewBuilder
    private var editorBody: some View {
        if let tab = appState.activeTab, let bookID = tab.bookID {
            EPUBReaderHost(bookID: bookID)
                .id(bookID)
                .environmentObject(vault)
        } else if let tabIndex = appState.activeTabIndex {
            editorContent(for: tabIndex)
        } else {
            emptyState
        }
    }

    private func insertSnippet(text: String, cursorOffset: Int) {
        guard appState.activeTabIndex != nil else { return }
        // Signal the native editor to insert at its current cursor position.
        // The editor's Coordinator picks this up in updateNSView/updateUIView and
        // uses NSTextView.insertText / UITextView.replace — both of which are
        // automatically tracked by the system undo manager.
        appState.pendingSnippet = SnippetInsert(text: text, cursorOffset: cursorOffset)
    }

    @ViewBuilder
    private func editorContent(for tabIndex: Int) -> some View {
        let tab = appState.openTabs[tabIndex]

        // Media tabs (.mp4/.mov/.mp3/...) bypass the editor entirely.
        if let mediaURL = mediaURL(for: tab),
           let kind = MediaKind.from(url: mediaURL) {
            if kind == .image {
                ImagePreviewView(url: mediaURL)
            } else {
                MediaPlayerView(url: mediaURL, kind: kind)
            }
        }
        // _dashboard.md is just a markdown file — open it in the regular
        // editor. The separate split / regenerate chrome is gone per user
        // request; AI dashboard content is generated via the AI menu and
        // written to disk as plain markdown, same as any other note.
        else {
            let baseURL = noteBaseURL(for: tab)
            switch appState.previewMode {
            case .editor:
                EditorView(document: tab.document)
            case .split:
                HSplitOrVStack {
                    EditorView(document: tab.document)
                    MarkdownPreviewView(content: tab.document.content, baseURL: baseURL)
                }
            case .preview:
                MarkdownPreviewView(content: tab.document.content, baseURL: baseURL)
            }
        }
    }

    /// Return the on-disk URL for a vault-backed tab if (and only if) it
    /// points to a playable media file. Returns nil for regular notes.
    private func mediaURL(for tab: TabItem) -> URL? {
        if let external = tab.externalMediaURL {
            return external
        }
        guard preferences.vaultMode,
              let relPath = appState.vaultPath(forTabId: tab.id),
              let url = vault.url(for: relPath),
              MediaKind.from(url: url) != nil
        else { return nil }
        return url
    }

    /// Directory that markdown preview should resolve relative links against.
    /// For vault notes this is the note's parent folder; for legacy flat
    /// tabs we have no disk location, so return nil (preview falls back to
    /// the temp dir — matches previous behavior).
    private func noteBaseURL(for tab: TabItem) -> URL? {
        guard preferences.vaultMode,
              let relPath = appState.vaultPath(forTabId: tab.id),
              let fileURL = vault.url(for: relPath)
        else { return nil }
        return fileURL.deletingLastPathComponent()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Document Open")
                .font(.title2)
                .foregroundStyle(.secondary)
            Button("New Document") { createNewDocument() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - New-document routing
    //
    // Vault mode writes a blank .md to the current sidebar selection (falling
    // back to the vault root) and opens it as a tab. Legacy mode falls back
    // to the old SwiftData TextDocument path.

    private func createNewDocument() {
        if preferences.vaultMode {
            let parent = targetFolderForNew()
            Task { await createVaultNote(inFolder: parent) }
        } else {
            let defaultType = FileType(rawValue: preferences.defaultFileType) ?? .txt
            let doc = TextDocument(fileType: defaultType)
            modelContext.insert(doc)
            appState.openNewTab(document: doc)
        }
    }

    @MainActor
    private func createVaultNote(inFolder parent: String) async {
        do {
            let newPath = try await vault.createNote(inFolder: parent, title: "Untitled")
            guard let url = vault.url(for: newPath) else { return }
            let title = ((newPath as NSString).lastPathComponent as NSString).deletingPathExtension
            appState.openVaultFile(relativePath: newPath) {
                let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return TextDocument(title: title, content: content, fileType: .md)
            }
            appState.selectedSidebarPath = newPath
        } catch {
            appState.lastSaveError = "Create note failed: \(error.localizedDescription)"
        }
    }

    /// Resolve sidebar selection to a folder path ("" = vault root). Files
    /// promote to their parent directory.
    private func targetFolderForNew() -> String {
        let sel = appState.selectedSidebarPath
        if sel.isEmpty { return "" }
        if let node = Self.findNode(matching: sel, in: vault.tree) {
            return node.isDirectory ? sel : (sel as NSString).deletingLastPathComponent
        }
        return ""
    }

    /// Flush the outgoing session, load the incoming one. Only vault-backed
    /// tabs get a session (the chat is path-keyed). Non-vault tabs leave
    /// `activeChatSession` nil and the panel renders its "open a note" state.
    private func syncChatSession() {
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

    private static func findNode(matching path: String, in tree: FolderNode) -> FolderNode? {
        if tree.relativePath == path { return tree }
        for child in tree.children {
            if child.relativePath == path { return child }
            if let hit = findNode(matching: path, in: child) { return hit }
        }
        return nil
    }

    private var focusModeView: some View {
        ZStack {
            #if os(macOS)
            Color(NSColor.textBackgroundColor).ignoresSafeArea()
            #else
            Color(UIColor.systemBackground).ignoresSafeArea()
            #endif

            if let tabIndex = appState.activeTabIndex {
                EditorView(document: appState.openTabs[tabIndex].document)
                    #if os(macOS)
                    .padding(.horizontal, 80)
                    .padding(.vertical, 40)
                    #else
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    #endif
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        withAnimation { appState.isFocusMode = false }
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 18))
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding()
                    .opacity(0.6)
                }
            }
        }
    }

    // MARK: - iOS Toolbar

    #if os(iOS)
    @ToolbarContentBuilder
    private var iOSToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                appState.showFileManager = true
            } label: {
                Image(systemName: "folder")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button { createNewDocument() } label: {
                Image(systemName: "plus")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.toggleSearch()
            } label: {
                Image(systemName: "magnifyingglass")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation { showAIPanel = true }
            } label: {
                Image(systemName: "brain")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            // More menu — contains preview mode, voice, focus, settings
            Menu {
                // Open file
                Button {
                    appState.showFileImporter = true
                } label: {
                    Label("Open File...", systemImage: "folder.badge.plus")
                }

                Divider()

                // Preview mode
                Menu {
                    ForEach(PreviewMode.allCases, id: \.self) { mode in
                        Button {
                            appState.previewMode = mode
                        } label: {
                            Label(mode.rawValue, systemImage: mode.iconName)
                        }
                    }
                } label: {
                    Label("Preview Mode", systemImage: "eye")
                }

                Divider()

                // Focus mode
                Button {
                    withAnimation { appState.isFocusMode = true }
                } label: {
                    Label("Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
                }

                Divider()

                // Settings
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
    #endif

    // MARK: - macOS Toolbar

    #if os(macOS)
    @ToolbarContentBuilder
    private var macToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.showFileImporter = true
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .accessibilityLabel("Open File")
            }
            .help("Open File (⌘O)")
            .keyboardShortcut("o", modifiers: .command)
        }

        ToolbarItem(placement: .primaryAction) {
            Button { createNewDocument() } label: {
                Image(systemName: "plus")
                    .accessibilityLabel("New Document")
            }
            .help("New Document")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.toggleSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .accessibilityLabel("Find in Document")
            }
            .help("Find… (⌘F)")
            .keyboardShortcut("f", modifiers: .command)
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(PreviewMode.allCases, id: \.self) { mode in
                    Button {
                        appState.previewMode = mode
                    } label: {
                        Label(mode.rawValue, systemImage: mode.iconName)
                    }
                }
            } label: {
                Image(systemName: appState.previewMode.iconName)
                    .accessibilityLabel("Preview Mode")
            }
            .help("Preview Mode")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation { showAIPanel.toggle() }
            } label: {
                Image(systemName: "brain")
                    .accessibilityLabel("AI Assistant")
            }
            .help("AI Assistant (⌘⇧I)")
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation { appState.isFocusMode = true }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .accessibilityLabel("Focus Mode")
            }
            .help("Focus Mode (⌘⇧\\)")
        }
    }
    #endif
}

// MARK: - iOS AI Panel as Sheet

#if os(iOS)
struct AIActionPanelSheetView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var aiService = AITextService.shared
    @Binding var isPresented: Bool

    @State private var selectedAction: AIAction = .polish
    @State private var result: String = ""
    @State private var isProcessing: Bool = false
    @State private var targetLanguage: String = "English"
    @State private var polishStyle: PolishStyle = .concise
    @State private var summaryLength: SummaryLength = .medium

    enum AIAction: String, CaseIterable, Identifiable {
        case polish = "Polish"
        case summarize = "Summarize"
        case continueWriting = "Continue"
        case translate = "Translate"
        case grammar = "Grammar"
        case simplify = "Simplify"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .polish: return "wand.and.stars"
            case .summarize: return "text.redaction"
            case .continueWriting: return "text.append"
            case .translate: return "globe"
            case .grammar: return "checkmark.circle"
            case .simplify: return "arrow.triangle.branch"
            }
        }
    }

    private var currentText: String {
        appState.activeTab?.document.content ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Model status
            if aiService.modelState != .ready {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("AI model not downloaded. Go to Settings → AI to download.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }

            // Action chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AIAction.allCases) { action in
                        Button {
                            selectedAction = action
                        } label: {
                            Label(action.rawValue, systemImage: action.icon)
                                .font(.system(size: 13))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedAction == action
                                    ? Color.accentColor.opacity(0.15)
                                    : Color(.secondarySystemBackground),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            Divider()

            // Options
            iOSActionOptions
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            // Result
            if isProcessing {
                HStack {
                    ProgressView()
                    Text("Processing...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if !result.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Result")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Copy") {
                            UIPasteboard.general.string = result
                        }
                        .font(.caption)
                        Button("Replace") {
                            replaceContent()
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                    }
                    ScrollView {
                        Text(result)
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }

            Spacer()

            // Run button
            HStack {
                Text("\(currentText.count) chars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await executeAction() }
                } label: {
                    Label("Run AI", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentText.isEmpty || isProcessing || aiService.modelState != .ready)
            }
            .padding()
        }
        .navigationTitle("AI Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { isPresented = false }
            }
        }
    }

    @ViewBuilder
    private var iOSActionOptions: some View {
        switch selectedAction {
        case .polish:
            Picker("Style", selection: $polishStyle) {
                ForEach(PolishStyle.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
        case .summarize:
            Picker("Length", selection: $summaryLength) {
                Text("Brief").tag(SummaryLength.brief)
                Text("Medium").tag(SummaryLength.medium)
                Text("Detailed").tag(SummaryLength.detailed)
            }
            .pickerStyle(.segmented)
        case .translate:
            Picker("To", selection: $targetLanguage) {
                Text("English").tag("English")
                Text("中文").tag("Simplified Chinese")
                Text("日本語").tag("Japanese")
                Text("한국어").tag("Korean")
                Text("Français").tag("French")
            }
            .pickerStyle(.segmented)
        default:
            EmptyView()
        }
    }

    private func executeAction() async {
        isProcessing = true
        result = ""
        let text = currentText

        switch selectedAction {
        case .polish:
            result = await aiService.polish(text, style: polishStyle)
        case .summarize:
            result = await aiService.summarize(text, length: summaryLength)
        case .continueWriting:
            var acc = ""
            for await chunk in await aiService.continueWriting(text) {
                acc += chunk
                result = acc
            }
        case .translate:
            result = await aiService.translate(text, to: targetLanguage)
        case .grammar:
            let suggestions = await aiService.checkGrammar(text)
            result = suggestions.isEmpty
                ? "No issues found."
                : suggestions.map { "• \($0.original) → \($0.suggestion)" }.joined(separator: "\n")
        case .simplify:
            result = await aiService.polish(text, style: .concise)
        }
        isProcessing = false
    }

    private func replaceContent() {
        guard let index = appState.activeTabIndex else { return }
        appState.openTabs[index].document.content = result
        appState.openTabs[index].isModified = true
        isPresented = false
    }
}
#endif

private struct ImagePreviewView: View {
    let url: URL

    var body: some View {
        ZStack {
            #if os(macOS)
            Color(NSColor.textBackgroundColor)
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(24)
            } else {
                Text("Could not load image.")
                    .foregroundStyle(.secondary)
            }
            #else
            Color(uiColor: .systemBackground)
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(24)
            } else {
                Text("Could not load image.")
                    .foregroundStyle(.secondary)
            }
            #endif
        }
    }
}

// MARK: - Adaptive Split View

struct HSplitOrVStack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
        HSplitView {
            content()
        }
        #else
        GeometryReader { geo in
            if geo.size.width > 600 {
                HStack(spacing: 0) {
                    content()
                }
            } else {
                VStack(spacing: 0) {
                    content()
                }
            }
        }
        #endif
    }
}
