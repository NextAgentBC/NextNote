import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var vault: VaultStore
    @EnvironmentObject var libraryRoots: LibraryRoots
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
        // Save whenever the scene goes inactive (Cmd+Tab / home button / app switch)
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                saveAll()
            }
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
        // Drawing window opens via DrawingWindowController in EditorAreaView's
        // toolbar action — no sheet wiring needed here.
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
        await BookLibrary.scan(
            vault: vault,
            ebooksRoot: libraryRoots.ebooksRoot,
            context: modelContext
        )
        await MediaLibrary.shared.scanRoot(libraryRoots.mediaRoot)
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
