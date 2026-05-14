import SwiftUI
import SwiftData

@main
struct NextNoteApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var vaultStore = VaultStore()
    @StateObject private var libraryRoots = LibraryRoots()
    @StateObject private var assetCatalog = AssetCatalog()
    @StateObject private var pinnedFolders = PinnedFoldersStore()
    @StateObject private var backlinksIndex = BacklinksIndex()
    @StateObject private var tagsIndex = TagsIndex()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: NextNoteSchemaV7.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(vaultStore)
                .environmentObject(libraryRoots)
                .environmentObject(assetCatalog)
                .environmentObject(pinnedFolders)
                .environmentObject(backlinksIndex)
                .environmentObject(tagsIndex)
                .frame(minWidth: 700, minHeight: 500)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            NextNoteCommands(appState: appState, libraryRoots: libraryRoots, pinnedFolders: pinnedFolders, vault: vaultStore)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(vaultStore)
                .environmentObject(libraryRoots)
                .environmentObject(assetCatalog)
                .environmentObject(pinnedFolders)
                .environmentObject(backlinksIndex)
                .environmentObject(tagsIndex)
        }
        #else
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(vaultStore)
                .environmentObject(libraryRoots)
                .environmentObject(assetCatalog)
                .environmentObject(pinnedFolders)
                .environmentObject(backlinksIndex)
                .environmentObject(tagsIndex)
        }
        .modelContainer(sharedModelContainer)
        #endif
    }
}
