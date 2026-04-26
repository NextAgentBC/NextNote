import SwiftUI

// Always-available shortcut reference. ⌘/ toggles. Shown as a floating
// panel — non-modal, can stay open while you work; ⌘/ again or ✕ closes.
struct ShortcutCheatsheet: View {
    @EnvironmentObject private var appState: AppState

    private struct Row: Identifiable {
        let id = UUID()
        let keys: String
        let label: String
    }

    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let rows: [Row]
    }

    private var sections: [Section] {
        [
            Section(title: "Workflow (AI)", rows: [
                Row(keys: "⌘K",   label: "Run skill — command palette"),
                Row(keys: "⌘⇧T",  label: "Toggle terminal pane"),
                Row(keys: "⌘⇧D",  label: "Open today's daily note"),
                Row(keys: "⌘⇧N",  label: "Quick capture (URL / paste → swipe / inbox / ingest)"),
            ]),
            Section(title: "File / Edit", rows: [
                Row(keys: "⌘O",   label: "Open file"),
                Row(keys: "⌘T",   label: "New tab"),
                Row(keys: "⌘W",   label: "Close tab"),
                Row(keys: "⌘S",   label: "Save"),
                Row(keys: "⌘F",   label: "Find in document"),
            ]),
            Section(title: "View", rows: [
                Row(keys: "⌘⇧\\", label: "Focus mode"),
                Row(keys: "⌃⌘S",  label: "Toggle sidebar"),
            ]),
            Section(title: "Help", rows: [
                Row(keys: "⌘/",   label: "Toggle this cheatsheet"),
            ]),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 420)
        .frame(maxHeight: 540)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(systemName: "command")
                .foregroundStyle(.secondary)
            Text("Shortcuts")
                .font(.headline)
            Spacer()
            Button {
                appState.showShortcuts = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func sectionView(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            VStack(spacing: 0) {
                ForEach(section.rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        keyPill(row.keys)
                        Text(row.label)
                            .font(.system(size: 12))
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func keyPill(_ keys: String) -> some View {
        Text(keys)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .frame(width: 60, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Text("⌘/ to toggle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("Workflow menu = same shortcuts")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
