import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var vault: VaultStore
    @EnvironmentObject var libraryRoots: LibraryRoots
    @EnvironmentObject var backlinksIndex: BacklinksIndex
    @EnvironmentObject var tagsIndex: TagsIndex
    @Environment(\.modelContext) var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \TextDocument.modifiedAt, order: .reverse) private var documents: [TextDocument]
    @StateObject var preferences = UserPreferences.shared
    @State var showSettings = false
    @State private var showAmbientFolderPrompt = false
    /// Last rescan timestamp — used to debounce focus-rescan against rapid
    /// app-switch loops (Cmd-Tab / mission control).
    @State private var lastRescanAt: Date = .distantPast

    @ViewBuilder
    private var rootView: some View {
        if preferences.vaultMode && !libraryRoots.isConfigured {
            LibrarySetupView()
                .environmentObject(libraryRoots)
        } else if appState.isFocusMode {
            FocusModeView()
        } else {
            mainLayout
        }
    }

    var body: some View {
        rootView
        .onAppear {
            libraryRoots.migrateLegacyVaultBookmarkIfNeeded()
            // One-time: unify the sidebar under a single root — the parent of
            // the old Notes folder (which holds notes/Media/ebooks as subfolders).
            if !UserDefaults.standard.bool(forKey: "nextnote.unifyRootDone") {
                if let notes = libraryRoots.notesRoot {
                    libraryRoots.adopt(kind: .notes, url: notes.deletingLastPathComponent())
                }
                UserDefaults.standard.set(true, forKey: "nextnote.unifyRootDone")
            }
            vault.adoptNotesRoot(libraryRoots.notesRoot)
            // Backlinks index follows vault tree changes from here on.
            backlinksIndex.wireToVault(vault)
            tagsIndex.wireToVault(vault)
        }
        // Finder "Open With NextNote" / "Always Open With" / default-app double-click.
        // Routes md/text → tab, pdf/epub → Book library import + book tab.
        .onOpenURL { url in
            appState.openExternalFile(url: url, vault: vault, context: modelContext)
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
        }
        // Defer MediaLibrary's bookmark resolution + file-exists prune off the
        // main thread — used to freeze launch when the library had >100 tracks.
        // bootstrap() is idempotent; the ambient-folder prompt waits until it
        // finishes so shouldPromptForAmbientFolder reflects restored state.
        .task {
            await MediaLibrary.shared.bootstrap()
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
        .onChange(of: appState.triggerRescanMedia) { _, v in
            if v {
                appState.triggerRescanMedia = false
                Task { await MediaLibrary.shared.scanRoot(libraryRoots.mediaRoot) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reembedLibraryRequested)) { _ in
            Task { @MainActor in await reembedLibrary() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextNoteWikiLinkClicked)) { note in
            guard let target = note.userInfo?["target"] as? String else { return }
            handleWikiLinkClick(target: target)
        }
        // Rescan whenever the window regains focus — user dropped a file in
        // Finder, switches back, expects to see it instantly. Debounce kept
        // generous (60s) because the focus event fires on every Cmd-Tab and
        // each rescan walks three trees (vault + ebooks + media).
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            let now = Date()
            if now.timeIntervalSince(lastRescanAt) < 60 { return }
            lastRescanAt = now
            Task { await rescanLibrary() }
        }
        #endif
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
        // New Drawing (⌃⌘D) — create a .nndraw note in the target folder.
        .onChange(of: appState.triggerNewDrawing) { _, v in
            guard v else { return }
            appState.triggerNewDrawing = false
            let parent = targetFolderForNew()
            Task { await createDrawingNote(inFolder: parent) }
        }
        // Save whenever the scene goes inactive (Cmd+Tab / home button / app switch)
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                saveAll()
            }
        }
        // Quick switcher (⌘P) — fuzzy-find any vault file by name.
        .sheet(isPresented: $appState.showQuickSwitcher) {
            QuickSwitcherSheet()
                .environmentObject(appState)
                .environmentObject(vault)
        }
        // AI summary sheet — triggered by Workflow > AI Summarize Note.
        .sheet(isPresented: Binding(
            get: { appState.pendingAISummary != nil },
            set: { if !$0 { appState.pendingAISummary = nil } }
        )) {
            AISummarySheet(sourceText: appState.pendingAISummary ?? "")
                .environmentObject(appState)
        }
        // Tags browser — triggered by Workflow > Browse Tags.
        .sheet(isPresented: $appState.showTagsBrowser) {
            TagsBrowserSheet()
                .environmentObject(appState)
                .environmentObject(vault)
                .environmentObject(tagsIndex)
        }
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
        // YouTube download history — submitted jobs run in background,
        // user watches progress + retries / cancels here.
        .sheet(isPresented: $appState.showDownloadHistory) {
            DownloadHistoryView()
                .environmentObject(appState)
                .environmentObject(libraryRoots)
        }
        // Asset Library sheet — grid browser for the fourth library root
        // (images / video / audio). Cells are draggable onto the markdown
        // editor, which turns the drop into `![](…)` syntax.
        .sheet(isPresented: $appState.showAssetLibrary) {
            AssetLibraryView()
                .environmentObject(appState)
                .environmentObject(libraryRoots)
        }
        #if os(macOS)
        // Reconcile / Dedupe sheet — AI groups duplicate artist folders and
        // detects duplicate tracks for batch cleanup.
        .sheet(isPresented: $appState.showReconcileLibrary) {
            LibraryReconcileSheet()
                .environmentObject(appState)
                .environmentObject(libraryRoots)
        }
        // Floating preview window — toggled via View > Floating Preview
        // (⌘⇧P) or the toolbar pop-out button. Opens / closes a standalone
        // NSWindow that mirrors the active note's rendered markdown so it
        // can be screen-shared in video calls.
        .onChange(of: appState.triggerFloatingPreviewToggle) { _, trigger in
            guard trigger else { return }
            appState.triggerFloatingPreviewToggle = false
            if PreviewWindowController.shared.isOpen {
                PreviewWindowController.shared.close()
            } else {
                PreviewWindowController.shared.show(
                    appState: appState,
                    vault: vault,
                    libraryRoots: libraryRoots,
                    preferences: preferences
                )
            }
        }
        #endif
        // PDF export trigger — File > Export > PDF…
        #if os(macOS)
        .onChange(of: appState.triggerExportPDF) { _, triggered in
            guard triggered else { return }
            appState.triggerExportPDF = false
            exportActiveNoteAsPDF()
        }
        #endif
        // File importer: supports both toolbar button and macOS menu (via appState.showFileImporter)
        .fileImporter(
            isPresented: $appState.showFileImporter,
            allowedContentTypes: FileType.openableUTTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                FileImportRouter.importFiles(urls: urls, vault: vault, appState: appState, modelContext: modelContext)
            case .failure: break
            }
        }
    }

    private func saveAll() {
        VaultSaveCoordinator.saveAll(
            modelContext: modelContext,
            vaultMode: preferences.vaultMode,
            appState: appState,
            vault: vault
        )
    }

    @MainActor
    private func rescanLibrary() async {
        // Ebooks/PDFs now live in the unified file tree (Books are created on
        // demand when opened), so the separate Ebooks-folder scan is gone.
        // Media still feeds the ambient player.
        await MediaLibrary.shared.scanRoot(libraryRoots.mediaRoot)
    }

    /// Resolve a clicked `[[wiki-link]]` target against the vault tree and
    /// open the matching note. Falls back to creating a new note at the
    /// vault root when the target doesn't exist yet — matches the Obsidian
    /// flow users expect.
    private func handleWikiLinkClick(target: String) {
        let paths = WikiLinkResolver.indexNotes(in: vault.tree)
        if let hit = WikiLinkResolver.resolve(target: target, paths: paths),
           let url = vault.url(for: hit) {
            let ext = (hit as NSString).pathExtension.lowercased()
            let isBinary = ext == "pdf" || ext == "epub" || VaultStore.imageExts.contains(ext)
            let title = ((hit as NSString).lastPathComponent as NSString).deletingPathExtension
            appState.openVaultFile(relativePath: hit) {
                let content = isBinary
                    ? ""
                    : (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                return TextDocument(title: title, content: content, fileType: FileType.from(url: url))
            }
            appState.selectedSidebarPath = hit
            return
        }

        // Miss → spawn a new note at the vault root with the target as the
        // title. User can move it from the sidebar afterwards.
        Task {
            do {
                let header = "# \(target)\n\n"
                let newPath = try await vault.createNote(
                    inFolder: "",
                    title: target,
                    initialContent: header
                )
                appState.openVaultFile(relativePath: newPath) {
                    TextDocument(title: target, content: header, fileType: .md)
                }
                appState.selectedSidebarPath = newPath
            } catch {
                appState.lastSaveError = "Could not create note for [[\(target)]]: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func reembedLibrary() async {
        let descriptor = FetchDescriptor<Book>()
        guard let books = try? modelContext.fetch(descriptor) else { return }
        try? await appState.embeddingPipeline.embedLibrary(
            books: books,
            chapterTextsProvider: { @MainActor book in
                await EPUBImporter.allChapterTexts(book: book, vault: vault)
            },
            progress: nil
        )
    }

    // MARK: - Sidebar

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
        .overlay(alignment: .bottomTrailing) {
            if appState.showShortcuts {
                ShortcutCheatsheet()
                    .environmentObject(appState)
                    .padding(.trailing, 80)
                    .padding(.bottom, 60)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: appState.showShortcuts)
        // AI chat terminal opens via ⌘⇧K in NextNoteCommands → toggles
        // appState.showChatBall, which we observe here and route through
        // `ChatTerminalWindowController` so the terminal lives in a
        // standalone NSWindow (Warp-style) instead of as an in-window panel.
        .onChange(of: appState.showChatBall) { _, show in
            if show {
                ChatTerminalWindowController.shared.show(appState: appState)
            } else {
                ChatTerminalWindowController.shared.close()
            }
        }
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
}
