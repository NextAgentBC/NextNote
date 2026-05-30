import SwiftUI
import SwiftData

@main
struct NextNoteApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var vaultStore = VaultStore()
    @StateObject private var projectStore = ProjectStore()
    @StateObject private var assetCatalog = AssetCatalog()
    @StateObject private var pinnedFolders = PinnedFoldersStore()
    @StateObject private var backlinksIndex = BacklinksIndex()
    @StateObject private var tagsIndex = TagsIndex()

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(vaultStore)
                .environmentObject(projectStore)
                .environmentObject(assetCatalog)
                .environmentObject(pinnedFolders)
                .environmentObject(backlinksIndex)
                .environmentObject(tagsIndex)
                .frame(minWidth: 700, minHeight: 500)
        }
        .commands {
            NextNoteCommands(
                appState: appState,
                projectStore: projectStore,
                pinnedFolders: pinnedFolders,
                vault: vaultStore
            )
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(vaultStore)
                .environmentObject(projectStore)
                .environmentObject(assetCatalog)
                .environmentObject(pinnedFolders)
                .environmentObject(backlinksIndex)
                .environmentObject(tagsIndex)
        }
        #else
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(vaultStore)
                .environmentObject(projectStore)
                .environmentObject(assetCatalog)
                .environmentObject(pinnedFolders)
                .environmentObject(backlinksIndex)
                .environmentObject(tagsIndex)
        }
        #endif
    }
}

/// Picks WelcomeView when no project is open; ProjectShellView (which
/// owns the per-project ModelContainer) otherwise. Keyed by project URL
/// so switching projects fully tears down the previous shell.
struct RootView: View {
    @EnvironmentObject private var projectStore: ProjectStore

    var body: some View {
        if let url = projectStore.current {
            ProjectShellView(projectURL: url)
                .id(url)
        } else {
            WelcomeView()
        }
    }
}

/// Builds the SwiftData ModelContainer rooted in
/// `<project>/.nextnote/library.store` and hands it to ContentView. Lives
/// only as long as the current project — `.id(url)` in RootView guarantees
/// a fresh instance on switch.
struct ProjectShellView: View {
    let projectURL: URL
    @State private var container: ModelContainer?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let container {
                ContentView()
                    .modelContainer(container)
            } else if let loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text("Couldn't open project library")
                        .font(.headline)
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: projectURL) {
            do {
                container = try buildContainer(at: projectURL)
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private func buildContainer(at url: URL) throws -> ModelContainer {
        let metaDir = url.appendingPathComponent(".nextnote", isDirectory: true)
        try FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)
        let storeURL = metaDir.appendingPathComponent("library.store", isDirectory: false)
        let schema = Schema(versionedSchema: NextNoteSchemaV7.self)
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
