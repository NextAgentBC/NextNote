import SwiftUI

struct EditorSettingsView: View {
    @StateObject private var prefs = UserPreferences.shared

    var body: some View {
        Form {
            Section("New Document") {
                Picker("Default Format", selection: $prefs.defaultFileType) {
                    ForEach(FileType.allCases) { type in
                        Text(type.displayName).tag(type.rawValue)
                    }
                }
            }

            Section("Editing") {
                Toggle("Auto Indent", isOn: $prefs.autoIndent)

                Picker("Tab Width", selection: $prefs.tabWidth) {
                    Text("2 spaces").tag(2)
                    Text("4 spaces").tag(4)
                    Text("8 spaces").tag(8)
                }
            }

            Section("Auto Save") {
                Picker("Interval", selection: $prefs.autoSaveInterval) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("Manual only").tag(0)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Editor")
    }
}
