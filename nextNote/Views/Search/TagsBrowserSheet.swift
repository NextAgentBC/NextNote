import SwiftUI

// Two-pane tag browser. Left column lists every tag in the vault with
// its note count; right column shows the notes that carry the selected
// tag. Click a note → opens as a tab, dismisses the sheet.
//
// Triggered from Workflow > Browse Tags (⌘T currently free).
struct TagsBrowserSheet: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var tagsIndex: TagsIndex
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTag: String?
    @State private var search: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                tagList
                Divider()
                notesList
            }
        }
        .frame(width: 640, height: 440)
        .task {
            await refreshIfStale()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "tag")
                .foregroundStyle(.tint)
            Text("Tags")
                .font(.system(size: 14, weight: .semibold))
            if tagsIndex.isBuilding {
                ProgressView().controlSize(.small).padding(.leading, 4)
            }
            Spacer()
            TextField("Filter…", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button {
                Task { await rebuild() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
    }

    private var sortedTags: [(tag: String, count: Int)] {
        tagsIndex.entries
            .map { (tag: $0.key, count: $0.value.count) }
            .filter { search.isEmpty || $0.tag.localizedCaseInsensitiveContains(search) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.tag < rhs.tag
            }
    }

    @ViewBuilder
    private var tagList: some View {
        let items = sortedTags
        if items.isEmpty {
            VStack {
                Spacer()
                Text(tagsIndex.isBuilding ? "Scanning…" : "No tags yet")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(width: 220)
        } else {
            List(selection: $selectedTag) {
                ForEach(items, id: \.tag) { item in
                    HStack {
                        Text("#\(item.tag)")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(item.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .tag(item.tag)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 220)
        }
    }

    @ViewBuilder
    private var notesList: some View {
        if let tag = selectedTag, let notes = tagsIndex.entries[tag] {
            VStack(alignment: .leading, spacing: 0) {
                Text("#\(tag)")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                Text("\(notes.count) note(s)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(notes, id: \.self) { path in
                            noteRow(path: path)
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "tag.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("Pick a tag to see notes")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func noteRow(path: String) -> some View {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let parent = (path as NSString).deletingLastPathComponent
        return Button {
            openNote(path: path)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                if !parent.isEmpty {
                    Text(parent)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func openNote(path: String) {
        guard let url = vault.url(for: path) else { return }
        let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        appState.openVaultFile(relativePath: path) {
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return TextDocument(title: title, content: content, fileType: .md)
        }
        appState.selectedSidebarPath = path
        dismiss()
    }

    private func refreshIfStale() async {
        // 30s freshness window — Browse Tags is rarely opened, so even a
        // mildly stale index is fine; the wireToVault path keeps it warm.
        if let builtAt = tagsIndex.builtAt, Date().timeIntervalSince(builtAt) < 30 {
            return
        }
        await rebuild()
    }

    private func rebuild() async {
        let paths = BacklinksIndex.collectMdPaths(in: vault.tree)
        await tagsIndex.rebuild(root: vault.root, mdRelativePaths: paths)
    }
}
