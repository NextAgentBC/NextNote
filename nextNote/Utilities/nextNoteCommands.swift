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
        }

        // Edit menu additions
        CommandGroup(after: .textEditing) {
            Button("Find...") {
                appState.toggleSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
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
                Task { @MainActor in AmbientPlayer.shared.togglePlayPause() }
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

            Button("Media Library") {
                appState.showMediaLibrary.toggle()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button("Asset Library") {
                appState.showAssetLibrary.toggle()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])

            // Cmd+Shift+V is "Paste and Match Style" in macOS text fields — skip
            // the shortcut here to avoid stealing it inside the editor.
            Button("Toggle Video Vibe Window") {
                Task { @MainActor in VideoVibeWindowController.shared.toggle() }
            }

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

            Button("Generate Playlists from Folders (AI)") {
                Task { @MainActor in
                    guard let root = MediaLibrary.shared.ambientFolderURL else { return }
                    _ = await MediaLibrary.shared.generatePlaylistsFromFolders(root: root)
                }
            }

            Divider()

            Button("Download from YouTube…") {
                appState.showYouTubeDownload = true
            }
        }

        // AI menu
        CommandMenu("AI") {
            Button("Rebuild All Dashboards") {
                Task { await DashboardService.shared.regenerateAll() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Run Daily Digest Now") {
                Task { await DailyDigestService.shared.runNow() }
            }

            Divider()

            Button("Summarize") {
                // TODO: AI summarize
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button("Polish") {
                // TODO: AI polish
            }

            Button("Continue Writing") {
                // TODO: AI continue
            }

            Button("Translate") {
                // TODO: AI translate
            }

            Button("Grammar Check") {
                // TODO: AI grammar check
            }
        }
    }

    private func navigateTab(direction: Int) {
        guard let currentIndex = appState.activeTabIndex,
              !appState.openTabs.isEmpty else { return }

        let newIndex = (currentIndex + direction + appState.openTabs.count) % appState.openTabs.count
        appState.activeTabId = appState.openTabs[newIndex].id
    }

    private func revealInFinder(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
#endif
