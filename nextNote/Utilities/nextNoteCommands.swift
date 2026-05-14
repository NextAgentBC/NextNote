import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
/// Mac menu bar commands
struct NextNoteCommands: Commands {
    @ObservedObject var appState: AppState
    @ObservedObject var libraryRoots: LibraryRoots
    @ObservedObject var pinnedFolders: PinnedFoldersStore
    @ObservedObject var vault: VaultStore

    var body: some Commands {
        // Replace the system "Save" entry so Cmd+S triggers our SwiftData save
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                appState.triggerSave = true
            }
            .keyboardShortcut("s", modifiers: .command)
        }

        // File menu additions
        CommandGroup(after: .newItem) {
            Button("Open File...") {
                appState.showFileImporter = true
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Quick Switcher…") {
                appState.showQuickSwitcher = true
            }
            .keyboardShortcut("p", modifiers: .command)

            Button("Daily Note") {
                Task { await appState.openDailyNote(vault: vault) }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Menu("Open Recent") {
                if appState.recentVaultFiles.isEmpty {
                    Text("No Recent Files")
                } else {
                    ForEach(appState.recentVaultFiles) { entry in
                        Button(entry.title.isEmpty ? entry.relativePath : entry.title) {
                            openRecent(entry)
                        }
                    }
                    Divider()
                    Button("Clear Menu") {
                        appState.clearRecentFiles()
                    }
                }
            }

            Divider()

            Button("New Tab") {
                appState.openNewTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Divider()

            Button("Close Tab") {
                if let id = appState.activeTabId {
                    appState.closeTab(id: id)
                }
            }
            .keyboardShortcut("w", modifiers: .command)

            Divider()

            Button("Export as PDF…") {
                appState.triggerExportPDF = true
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(appState.activeTab == nil)
        }

        // Edit menu additions
        CommandGroup(after: .textEditing) {
            Button("Find...") {
                appState.toggleSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        // Workflow menu — terminal and shortcuts toggles.
        CommandMenu("Workflow") {
            // Section 1 — terminals. Two distinct surfaces:
            //   • Shell (PTY): real /bin/zsh in the vault root for Claude
            //     Code / Gemini CLI / yt-dlp / git workflows.
            //   • AI Terminal (LLM): direct streaming chat, every prompt is a
            //     replayable block (Warp-style).
            Button(appState.showTerminal ? "Hide Shell" : "Show Shell") {
                appState.showTerminal.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button(appState.showChatBall ? "Hide AI Terminal" : "Show AI Terminal") {
                appState.showChatBall.toggle()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            // Section 2 — discoverability.
            Button(appState.showShortcuts ? "Hide Shortcuts" : "Show Shortcuts") {
                appState.showShortcuts.toggle()
            }
            .keyboardShortcut("/", modifiers: .command)

            Divider()

            Button("AI Summarize Note") {
                triggerAISummary()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(appState.activeTab == nil)

            Button("Browse Tags…") {
                appState.showTagsBrowser = true
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
        }

        // Merge into the system View menu (NavigationSplitView already adds
        // Show/Hide Sidebar ⌃⌘S). Using CommandGroup(after:) avoids the
        // duplicate top-level "View" menu a CommandMenu would create.
        CommandGroup(after: .sidebar) {
            Divider()

            Picker("Preview Mode", selection: $appState.previewMode) {
                ForEach(PreviewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            #if os(macOS)
            Button("Floating Preview") {
                appState.triggerFloatingPreviewToggle = true
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            #endif

            Divider()

            Button("Enter Focus Mode") {
                withAnimation { appState.isFocusMode = true }
            }
            .keyboardShortcut("\\", modifiers: [.command, .shift])
        }

        // Library menu — one-stop controls for Notes / Media / Ebooks roots.
        CommandMenu("Library") {
            Button("Open Folder in Sidebar…") {
                Task { await pinnedFolders.pickAndAdd() }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Change Notes Folder…") {
                Task { await libraryRoots.pick(kind: .notes) }
            }
            Button("Change Media Folder…") {
                Task { await libraryRoots.pick(kind: .media) }
            }
            Button("Change Ebooks Folder…") {
                Task { await libraryRoots.pick(kind: .ebooks) }
            }

            Divider()

            Button("Reveal Notes in Finder") {
                revealInFinder(libraryRoots.notesRoot)
            }
            .disabled(libraryRoots.notesRoot == nil)

            Button("Reveal Media in Finder") {
                revealInFinder(libraryRoots.mediaRoot)
            }
            .disabled(libraryRoots.mediaRoot == nil)

            Button("Reveal Ebooks in Finder") {
                revealInFinder(libraryRoots.ebooksRoot)
            }
            .disabled(libraryRoots.ebooksRoot == nil)

            Divider()

            Button("Rescan Library") {
                appState.triggerRescanLibrary = true
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        // Tab navigation
        CommandGroup(after: .toolbar) {
            Button("Next Tab") {
                navigateTab(direction: 1)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Previous Tab") {
                navigateTab(direction: -1)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            // ⌘1…⌘9 jump straight to tab N (⌘9 always goes to the last
            // tab so the binding is stable even with fewer tabs open).
            Group {
                Button("Tab 1") { activateTab(index: 0) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Tab 2") { activateTab(index: 1) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Tab 3") { activateTab(index: 2) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Tab 4") { activateTab(index: 3) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Tab 5") { activateTab(index: 4) }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Tab 6") { activateTab(index: 5) }
                    .keyboardShortcut("6", modifiers: .command)
                Button("Tab 7") { activateTab(index: 6) }
                    .keyboardShortcut("7", modifiers: .command)
                Button("Tab 8") { activateTab(index: 7) }
                    .keyboardShortcut("8", modifiers: .command)
                Button("Last Tab") { activateLastTab() }
                    .keyboardShortcut("9", modifiers: .command)
            }
        }

        // Media menu — ambient player control.
        // Chosen shortcuts avoid system bindings: media keys (F7/F8/F9) stay
        // with Music.app, Cmd+Space stays with Spotlight, F10–F12 stay with
        // system volume / mission control.
        CommandMenu("Media") {
            Button("Play / Pause") {
                Task { @MainActor in MediaPlayback.togglePlayPause() }
            }
            .keyboardShortcut(.space, modifiers: [.option])

            Button("Next Track") {
                Task { @MainActor in AmbientPlayer.shared.next() }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])

            Button("Previous Track") {
                Task { @MainActor in AmbientPlayer.shared.previous() }
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])

            Divider()

            Button("Shuffle Library") {
                Task { @MainActor in MediaPlayback.shuffleLibrary() }
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button("Toggle Loop") {
                Task { @MainActor in AmbientPlayer.shared.loop.toggle() }
            }
            .keyboardShortcut("l", modifiers: [.command, .option])

            Divider()

            Button("Media Library") {
                appState.showMediaLibrary.toggle()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button("Asset Library") {
                appState.showAssetLibrary.toggle()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            Button("Toggle Video Vibe Window") {
                Task { @MainActor in VideoVibeWindowController.shared.toggle() }
            }

            Divider()

            Button("Restore Titles") {
                appState.showMediaLibrary = true
                appState.triggerRestoreTitles = true
            }

            Button("Organize Library (AI)") {
                appState.showMediaLibrary = true
                appState.triggerOrganizeLibrary = true
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Reconcile / Dedupe (AI)…") {
                appState.showReconcileLibrary = true
            }
            .keyboardShortcut("o", modifiers: [.command, .shift, .option])

            Button("Rescan Media Folder") {
                appState.triggerRescanMedia = true
            }
            .keyboardShortcut("r", modifiers: [.command, .control])

            Divider()

            Button("Set Ambient Library Folder…") {
                Task { @MainActor in
                    _ = await MediaLibrary.shared.pickAmbientFolder()
                }
            }

            Button("Rescan Ambient Library") {
                Task { @MainActor in
                    await MediaLibrary.shared.scanAmbientFolder()
                }
            }

            Divider()

            Button("Download from YouTube…") {
                appState.showYouTubeDownload = true
            }
            .keyboardShortcut("y", modifiers: [.command, .shift])

            Button("Download History…") {
                appState.showDownloadHistory = true
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
        }

    }

    private func navigateTab(direction: Int) {
        guard let currentIndex = appState.activeTabIndex,
              !appState.openTabs.isEmpty else { return }

        let newIndex = (currentIndex + direction + appState.openTabs.count) % appState.openTabs.count
        appState.activeTabId = appState.openTabs[newIndex].id
    }

    private func activateTab(index: Int) {
        guard index >= 0, index < appState.openTabs.count else { return }
        appState.activeTabId = appState.openTabs[index].id
    }

    private func activateLastTab() {
        guard let last = appState.openTabs.last else { return }
        appState.activeTabId = last.id
    }

    private func revealInFinder(_ url: URL?) {
        FinderActions.reveal(url)
    }

    private func triggerAISummary() {
        guard let tab = appState.activeTab else { return }
        let text = tab.document.content
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        appState.pendingAISummary = text
    }

    private func openRecent(_ entry: RecentVaultEntry) {
        guard let url = vault.url(for: entry.relativePath) else { return }
        let ext = (entry.relativePath as NSString).pathExtension.lowercased()
        let isBinary = ext == "pdf" || ext == "epub" || VaultStore.imageExts.contains(ext)
        let title = entry.title.isEmpty
            ? ((entry.relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
            : entry.title
        appState.openVaultFile(relativePath: entry.relativePath) {
            let content = isBinary
                ? ""
                : (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return TextDocument(title: title, content: content, fileType: FileType.from(url: url))
        }
        appState.selectedSidebarPath = entry.relativePath
    }
}
#endif
