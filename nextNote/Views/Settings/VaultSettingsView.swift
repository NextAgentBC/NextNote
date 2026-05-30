import SwiftUI

struct VaultSettingsView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var vault: VaultStore

    var body: some View {
        Form {
            Section {
                if let root = projectStore.current {
                    LabeledContent("Current project") {
                        Text(root.path)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    HStack {
                        Button {
                            Task { _ = await projectStore.pick() }
                        } label: { Text("Open Project…") }
                        Button(role: .destructive) {
                            projectStore.close()
                        } label: { Text("Close Project") }
                        Spacer()
                        Button {
                            Task { await vault.scan() }
                        } label: { Text("Rescan") }
                            .disabled(vault.isScanning)
                    }
                } else {
                    Button {
                        Task { _ = await projectStore.pick() }
                    } label: { Text("Open Project…") }
                }

                if let err = vault.lastError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Project")
            } footer: {
                Text("A project is one folder. NextNote keeps its library at `<project>/.nextnote/library.store` so notes and metadata travel together.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Project")
    }
}
