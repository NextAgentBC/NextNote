import SwiftUI

// ⌘K overlay — lists discovered slash-skills from the active vault. Selecting
// a row sends `claude -p "/<slug>"` into the embedded terminal (auto-opens
// the pane if hidden).
struct CommandPalette: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var libraryRoots: LibraryRoots

    @State private var query: String = ""
    @State private var selection: Int = 0
    @State private var skills: [DiscoveredSkill] = []

    private var filtered: [DiscoveredSkill] {
        SkillDiscovery.rank(skills, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            input
            Divider()
            if filtered.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(width: 560)
        .frame(maxHeight: 460)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .onAppear {
            skills = SkillDiscovery.scan(vaultRoot: libraryRoots.notesRoot)
            query = ""
            selection = 0
        }
        .onChange(of: query) { _, _ in selection = 0 }
    }

    // MARK: - Sections

    private var input: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            TextField("Run a skill / slash command…", text: $query, onCommit: runSelected)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .onKeyPress { keyPress in
                    switch keyPress.key {
                    case .downArrow:
                        selection = min(selection + 1, max(filtered.count - 1, 0))
                        return .handled
                    case .upArrow:
                        selection = max(selection - 1, 0)
                        return .handled
                    case .escape:
                        appState.showCommandPalette = false
                        return .handled
                    default:
                        return .ignored
                    }
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, skill in
                        row(skill, index: idx, isSelected: idx == selection)
                            .id(idx)
                            .onTapGesture {
                                selection = idx
                                runSelected()
                            }
                    }
                }
            }
            .onChange(of: selection) { _, new in
                withAnimation(.linear(duration: 0.08)) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
    }

    private func row(_ skill: DiscoveredSkill, index: Int, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("/")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 14, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(skill.slug)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.white : .primary)
                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.9) : Color.clear)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Text(skills.isEmpty ? "No skills found in this vault." : "No match.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if skills.isEmpty {
                Text("Run 'Use AI Soul preset' in Library setup to seed.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            footerChip("↵", "Run in terminal")
            footerChip("⌘↵", "Run in terminal (bg-safe)")
            footerChip("⎋", "Close")
            Spacer()
            Text("\(filtered.count) skills")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func footerChip(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption2.monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func runSelected() {
        guard filtered.indices.contains(selection) else { return }
        let skill = filtered[selection]
        dispatch(skill)
    }

    private func dispatch(_ skill: DiscoveredSkill) {
        // Command palette's job: compose the command string, inject into the
        // terminal, make sure the pane is visible.
        let command = "claude \"/\(skill.slug)\""
        appState.showTerminal = true
        appState.pendingTerminalCommand = command
        appState.showCommandPalette = false
    }
}
