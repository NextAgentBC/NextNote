import SwiftUI

extension ContentView {
    @ViewBuilder
    var editorAndDock: some View {
        editorBody
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
        } else if let drawURL = drawingURL(for: tab) {
            DrawingDocumentView(fileURL: drawURL)
                .id(drawURL)
        } else {
            let baseURL = noteBaseURL(for: tab)
            if let sidecar = drawingSidecarURL(for: tab) {
                VStack(spacing: 0) {
                    modePicker(for: tabIndex)
                    Divider()
                    if appState.openTabs.indices.contains(tabIndex),
                       appState.openTabs[tabIndex].showDrawLayer {
                        DrawingDocumentView(fileURL: sidecar,
                                            markdownSource: tab.document.content,
                                            markdownBaseURL: baseURL)
                            .id(sidecar)
                    } else {
                        markdownBody(document: tab.document, baseURL: baseURL)
                    }
                }
            } else {
                markdownBody(document: tab.document, baseURL: baseURL)
            }
        }
    }

    /// The markdown editor/preview (without the Text/Draw chrome).
    @ViewBuilder
    func markdownBody(document: TextDocument, baseURL: URL?) -> some View {
        switch appState.previewMode {
        case .editor:
            EditorView(document: document)
        case .split:
            HSplitOrVStack {
                EditorView(document: document)
                MarkdownPreviewView(content: document.content, baseURL: baseURL)
            }
        case .preview:
            MarkdownPreviewView(content: document.content, baseURL: baseURL)
        }
    }

    /// Text | Draw switcher shown atop markdown notes.
    @ViewBuilder
    func modePicker(for tabIndex: Int) -> some View {
        Picker("", selection: Binding(
            get: { appState.openTabs.indices.contains(tabIndex) ? appState.openTabs[tabIndex].showDrawLayer : false },
            set: { if appState.openTabs.indices.contains(tabIndex) { appState.openTabs[tabIndex].showDrawLayer = $0 } }
        )) {
            Text("Text").tag(false)
            Text("Draw").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Hidden drawing sidecar next to a markdown note: `.<base>.nndraw`.
    /// Hidden (dot-prefixed) so the sidebar scanner skips it — one entry per note.
    func drawingSidecarURL(for tab: TabItem) -> URL? {
        guard preferences.vaultMode,
              let rel = appState.vaultPath(forTabId: tab.id),
              (rel as NSString).pathExtension.lowercased() == "md",
              let fileURL = vault.url(for: rel)
        else { return nil }
        let dir = fileURL.deletingLastPathComponent()
        let base = fileURL.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent(".\(base).nndraw")
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

    /// Resolve a tab to its on-disk `.nndraw` URL, if it is a drawing note.
    /// Drives the EditorContentRouter branch that shows `DrawingDocumentView`.
    func drawingURL(for tab: TabItem) -> URL? {
        guard preferences.vaultMode,
              let relPath = appState.vaultPath(forTabId: tab.id),
              (relPath as NSString).pathExtension.lowercased() == "nndraw",
              let url = vault.url(for: relPath)
        else { return nil }
        return url
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
            // Unified note: one note does both text + drawing. Default opens
            // in Draw mode (user preference); toggle to Text to type.
            let parent = targetFolderForNew()
            Task { await createVaultNote(inFolder: parent, openInDraw: true) }
        } else {
            let defaultType = FileType(rawValue: preferences.defaultFileType) ?? .txt
            let doc = TextDocument(fileType: defaultType)
            modelContext.insert(doc)
            appState.openNewTab(document: doc)
        }
    }

    @MainActor
    func createVaultNote(inFolder parent: String, openInDraw: Bool = false) async {
        do {
            let newPath = try await vault.createNote(inFolder: parent, title: "Untitled")
            let title = ((newPath as NSString).lastPathComponent as NSString).deletingPathExtension
            // Skip on-disk read — vault.createNote writes initialContent="" so
            // the freshly-created file is empty by definition.
            appState.openVaultFile(relativePath: newPath) {
                TextDocument(title: title, content: "", fileType: .md)
            }
            if openInDraw, let idx = appState.activeTabIndex {
                appState.openTabs[idx].showDrawLayer = true
            }
            appState.selectedSidebarPath = newPath
        } catch {
            appState.lastSaveError = "Create note failed: \(error.localizedDescription)"
        }
    }

    /// Create a new `.nndraw` drawing note in `parent` and open it in a tab.
    /// Mirrors `createVaultNote`; the DrawingDocumentView loads/saves the file.
    @MainActor
    func createDrawingNote(inFolder parent: String) async {
        do {
            let newPath = try await vault.createDrawing(inFolder: parent, title: "Drawing")
            let title = ((newPath as NSString).lastPathComponent as NSString).deletingPathExtension
            appState.openVaultFile(relativePath: newPath) {
                TextDocument(title: title, content: "", fileType: .drawing)
            }
            appState.selectedSidebarPath = newPath
        } catch {
            appState.lastSaveError = "Create drawing failed: \(error.localizedDescription)"
        }
    }

    func targetFolderForNew() -> String {
        NewDocumentRouter.targetFolder(forSelection: appState.selectedSidebarPath, in: vault.tree)
    }
}
