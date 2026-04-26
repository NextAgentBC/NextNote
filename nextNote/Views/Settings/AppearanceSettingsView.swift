import SwiftUI

struct AppearanceSettingsView: View {
    @StateObject private var prefs = UserPreferences.shared

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Mode", selection: $prefs.themeMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }

            Section("Font") {
                Picker("Font", selection: $prefs.fontName) {
                    Text("SF Mono").tag("SF Mono")
                    Text("Menlo").tag("Menlo")
                    Text("Courier").tag("Courier")
                    Text("SF Pro").tag("SF Pro")
                    Text("New York").tag("New York")
                }

                HStack {
                    Text("Size: \(Int(prefs.fontSize))pt")
                    Slider(value: $prefs.fontSize, in: 12...36, step: 1)
                }

                HStack {
                    Text("Line Spacing: \(prefs.lineSpacing, specifier: "%.1f")")
                    Slider(value: $prefs.lineSpacing, in: 1.0...2.5, step: 0.1)
                }
            }

            Section("Display") {
                Toggle("Show Line Numbers", isOn: $prefs.showLineNumbers)
                Toggle("Wrap Lines", isOn: $prefs.wrapLines)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}
