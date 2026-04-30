import SwiftUI
import SwiftData

extension ContentView {
    var editorArea: some View {
        VStack(spacing: 0) {
            if appState.openTabs.count > 1 {
                TabBarView()
            }

            if appState.showSearchBar {
                SearchBarView()
            }

            if let tab = appState.activeTab,
               tab.bookID == nil,
               tab.document.fileType == .md,
               mediaURL(for: tab) == nil {
                MarkdownToolbarView(
                    onInsert: { text, offset in
                        insertSnippet(text: text, cursorOffset: offset)
                    },
                    onDrawing: {
                        openDrawingWindow()
                    }
                )
            }

            editorAndDock

            #if os(macOS)
            if appState.showTerminal {
                TerminalContainerView(workingDirectory: libraryRoots.notesRoot)
                    .environmentObject(appState)
                    .frame(minHeight: 152, idealHeight: 252, maxHeight: 452)
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

    var activeContentTitle: String {
        if let tab = appState.activeTab {
            if let bt = tab.bookTitle, !bt.isEmpty { return bt }
            let t = tab.document.title
            if !t.isEmpty { return t }
        }
        return "nextNote"
    }

    var activeContentSubtitle: String {
        if let tab = appState.activeTab, let id = tab.bookID {
            let desc = FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })
            if let b = try? modelContext.fetch(desc).first, let a = b.author, !a.isEmpty {
                return a
            }
            return ""
        }
        return vault.root?.lastPathComponent ?? ""
    }

    #if os(macOS)
    func openDrawingWindow() {
        let tab = appState.activeTab
        let url: URL? = {
            guard let tab,
                  preferences.vaultMode,
                  let rel = appState.vaultPath(forTabId: tab.id) else { return nil }
            return vault.url(for: rel)
        }()
        let baseName: String = {
            if let u = url { return u.deletingPathExtension().lastPathComponent }
            return tab?.document.title.replacingOccurrences(of: "/", with: "-") ?? "Untitled"
        }()
        DrawingWindowController.shared.show(
            noteURL: url,
            baseName: baseName,
            onSave: { [appState] relPath in
                let snippet = "![drawing](\(relPath))"
                appState.pendingSnippet = SnippetInsert(text: snippet, cursorOffset: snippet.count)
            }
        )
    }
    #endif
}
