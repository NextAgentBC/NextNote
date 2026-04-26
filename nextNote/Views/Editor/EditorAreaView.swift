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
}
