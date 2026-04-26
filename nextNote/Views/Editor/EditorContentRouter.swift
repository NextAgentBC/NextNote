import SwiftUI

extension ContentView {
    @ViewBuilder
    var editorAndDock: some View {
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
    var editorBody: some View {
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

    @ViewBuilder
    func editorContent(for tabIndex: Int) -> some View {
        let tab = appState.openTabs[tabIndex]

        if let mediaURL = mediaURL(for: tab),
           let kind = MediaKind.from(url: mediaURL) {
            if kind == .image {
                ImagePreviewView(url: mediaURL)
            } else {
                MediaPlayerView(url: mediaURL, kind: kind)
            }
        } else {
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

    func mediaURL(for tab: TabItem) -> URL? {
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

    func noteBaseURL(for tab: TabItem) -> URL? {
        guard preferences.vaultMode,
              let relPath = appState.vaultPath(forTabId: tab.id),
              let fileURL = vault.url(for: relPath)
        else { return nil }
        return fileURL.deletingLastPathComponent()
    }

    var emptyState: some View {
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

    func insertSnippet(text: String, cursorOffset: Int) {
        guard appState.activeTabIndex != nil else { return }
        appState.pendingSnippet = SnippetInsert(text: text, cursorOffset: cursorOffset)
    }

    func createNewDocument() {
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
    func createVaultNote(inFolder parent: String) async {
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

    func targetFolderForNew() -> String {
        NewDocumentRouter.targetFolder(forSelection: appState.selectedSidebarPath, in: vault.tree)
    }
}
