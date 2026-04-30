import SwiftUI

extension ContentView {
    // MARK: - iOS Toolbar

    #if os(iOS)
    @ToolbarContentBuilder
    var iOSToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                appState.showFileManager = true
            } label: {
                Image(systemName: "folder")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button { createNewDocument() } label: {
                Image(systemName: "plus")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.toggleSearch()
            } label: {
                Image(systemName: "magnifyingglass")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    appState.showFileImporter = true
                } label: {
                    Label("Open File...", systemImage: "folder.badge.plus")
                }

                Divider()

                Menu {
                    ForEach(PreviewMode.allCases, id: \.self) { mode in
                        Button {
                            appState.previewMode = mode
                        } label: {
                            Label(mode.rawValue, systemImage: mode.iconName)
                        }
                    }
                } label: {
                    Label("Preview Mode", systemImage: "eye")
                }

                Divider()

                Button {
                    withAnimation { appState.isFocusMode = true }
                } label: {
                    Label("Focus Mode", systemImage: "arrow.up.left.and.arrow.down.right")
                }

                Divider()

                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
    #endif

    // MARK: - macOS Toolbar

    #if os(macOS)
    @ToolbarContentBuilder
    var macToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.showFileImporter = true
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .accessibilityLabel("Open File")
            }
            .help("Open File (⌘O)")
            .keyboardShortcut("o", modifiers: .command)
        }

        ToolbarItem(placement: .primaryAction) {
            Button { createNewDocument() } label: {
                Image(systemName: "plus")
                    .accessibilityLabel("New Document")
            }
            .help("New Document")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.toggleSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .accessibilityLabel("Find in Document")
            }
            .help("Find… (⌘F)")
            .keyboardShortcut("f", modifiers: .command)
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(PreviewMode.allCases, id: \.self) { mode in
                    Button {
                        appState.previewMode = mode
                    } label: {
                        Label(mode.rawValue, systemImage: mode.iconName)
                    }
                }
                Divider()
                Button {
                    appState.triggerFloatingPreviewToggle = true
                } label: {
                    Label("Pop Out Preview…", systemImage: "rectangle.inset.filled.and.arrow.up.right")
                }
            } label: {
                Image(systemName: appState.previewMode.iconName)
                    .accessibilityLabel("Preview Mode")
            }
            .help("Preview Mode")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation { appState.isFocusMode = true }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .accessibilityLabel("Focus Mode")
            }
            .help("Focus Mode (⌘⇧\\)")
        }
    }
    #endif
}
