import SwiftUI

// Thin wrapper that labels the VaultTreeView as the Notes section of the
// sidebar. Keeps the existing tree rendering / context menus / drag-drop
// behavior intact.
struct NotesSection: View {
    @EnvironmentObject private var vault: VaultStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Notes")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                if let name = vault.root?.lastPathComponent {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            VaultTreeView()
        }
    }
}
