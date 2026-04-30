import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
/// Mac menu bar commands
struct NextNoteCommands: Commands {
    @ObservedObject var appState: AppState
    @ObservedObject var libraryRoots: LibraryRoots

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

    private func revealInFinder(_ url: URL?) {
        FinderActions.reveal(url)
    }
}
#endif
