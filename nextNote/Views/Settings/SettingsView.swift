import SwiftUI

struct SettingsView: View {
    @StateObject private var preferences = UserPreferences.shared
    @EnvironmentObject private var appState: AppState

    var body: some View {
        #if os(macOS)
        TabView {
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            EditorSettingsView()
                .tabItem { Label("Editor", systemImage: "doc.text") }
            VaultSettingsView()
                .tabItem { Label("Vault", systemImage: "folder") }
            SyncSettingsView()
                .tabItem { Label("Sync", systemImage: "icloud") }
            AISettingsView()
                .tabItem { Label("AI", systemImage: "brain") }
        }
        .frame(width: 520, height: 550)
        #else
        NavigationStack {
            List {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    Label("Appearance", systemImage: "paintbrush")
                }
                NavigationLink {
                    EditorSettingsView()
                } label: {
                    Label("Editor", systemImage: "doc.text")
                }
                NavigationLink {
                    SyncSettingsView()
                } label: {
                    Label("Sync", systemImage: "icloud")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
        #endif
    }
}
