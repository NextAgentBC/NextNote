import SwiftUI

// Empty-state shown when vaultMode is on but no vault has been chosen (or
// the saved bookmark went stale). One job: get the user to pick a folder.
struct VaultPickerView: View {
    @EnvironmentObject private var vault: VaultStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("No Vault Chosen")
                .font(.title2)

            Text("Pick a folder on disk to use as your nextNote vault. Your notes will live inside it as plain .md files — fully readable by Finder, git, Obsidian, anything.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            Button {
                Task { await vault.pickVault() }
            } label: {
                Label("Choose Vault…", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let err = vault.lastError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 440)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
