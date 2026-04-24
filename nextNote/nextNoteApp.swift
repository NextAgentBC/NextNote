import SwiftUI
import SwiftData

@main
struct NextNoteApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var vaultStore = VaultStore()
    @StateObject private var libraryRoots = LibraryRoots()
    @StateObject private var mediaCatalog = MediaCatalog()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: NextNoteSchemaV3.self)
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
                .environmentObject(mediaCatalog)
                .frame(minWidth: 700, minHeight: 500)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            NextNoteCommands(appState: appState, libraryRoots: libraryRoots)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(vaultStore)
                .environmentObject(libraryRoots)
                .environmentObject(mediaCatalog)
        }
        #else
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(vaultStore)
                .environmentObject(libraryRoots)
                .environmentObject(mediaCatalog)
        }
        .modelContainer(sharedModelContainer)
        #endif
    }
}
