import SwiftUI

struct VaultSettingsView: View {
    @StateObject private var prefs = UserPreferences.shared
    @EnvironmentObject private var vault: VaultStore

    var body: some View {
        Form {
            Section {
                Toggle("Enable vault mode (directory-backed)", isOn: $prefs.vaultMode)
                Text("Switches the sidebar from the flat SwiftData list to a real folder tree rooted at a folder on disk. Files stay as plain .md so Finder, git, and other editors work normally. Full disk-backed saves land in R2.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Vault Mode")
            }

            if prefs.vaultMode {
                Section {
                    if let root = vault.root {
                        LabeledContent("Current vault") {
                            Text(root.path)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        HStack {
                            Button {
                                Task { await vault.pickVault() }
                            } label: { Text("Change Vault…") }
                            Button(role: .destructive) {
                                vault.forgetVault()
                            } label: { Text("Forget Vault") }
                            Spacer()
                            Button {
                                Task { await vault.scan() }
                            } label: { Text("Rescan") }
                                .disabled(vault.isScanning)
                        }
                    } else {
                        Button {
                            Task { await vault.pickVault() }
                        } label: { Text("Choose Vault…") }
                    }

                    if let err = vault.lastError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Vault Folder")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Vault")
    }
}
