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
    @State var showAIPanel = false
    @State var showSettings = false
    @State private var showAmbientFolderPrompt = false

    var body: some View {
        Group {
            if preferences.vaultMode && !libraryRoots.isConfigured {
                LibrarySetupView()
                    .environmentObject(libraryRoots)
            } else if appState.isFocusMode {
                FocusModeView()
            } else {
                mainLayout
            }
        }
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
        .task {
            guard preferences.vaultMode else { return }
            await DailyDigestService.shared.generateIfDue()
        }
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
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await rescanLibrary() }
        }
        #endif
        .task(id: vault.root) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await rescanLibrary()
            }
        }
        .task(id: preferences.autoSaveInterval) {
            let interval = preferences.autoSaveInterval
            guard interval > 0 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                saveAll()
            }
        }
        .onChange(of: appState.triggerSave) { _, triggered in
            guard triggered else { return }
            saveAll()
            appState.triggerSave = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                saveAll()
            }
        }
        .onChange(of: appState.activeTabId) { _, _ in
            ChatSessionRouter.sync(appState: appState, vault: vault, preferences: preferences)
        }
        .onChange(of: vault.root) { _, _ in
            ChatSessionRouter.sync(appState: appState, vault: vault, preferences: preferences)
        }
        .onAppear {
            ChatSessionRouter.sync(appState: appState, vault: vault, preferences: preferences)
        }
        .sheet(isPresented: $appState.showMediaLibrary) {
            MediaLibraryView()
                .environmentObject(appState)
                .frame(minWidth: 760, minHeight: 460)
        }
        .sheet(isPresented: $appState.showYouTubeDownload) {
            YouTubeDownloadView()
        }
        .sheet(isPresented: $appState.showAssetLibrary) {
            AssetLibraryView()
                .environmentObject(appState)
                .environmentObject(libraryRoots)
        }
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
                Task { await rescanLibrary() }
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
}
