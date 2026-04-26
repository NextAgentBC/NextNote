import SwiftUI

struct SyncSettingsView: View {
    @StateObject private var prefs = UserPreferences.shared

    var body: some View {
        Form {
            Section("iCloud") {
                Toggle("Enable iCloud Sync", isOn: $prefs.enableICloudSync)
                Text("Documents will sync across your Apple devices via iCloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Sync")
    }
}
