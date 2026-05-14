import SwiftUI

// Modal quick-jump palette. Lists recent vault files (empty query) or
// substring/subsequence matches against every .md / .pdf / .epub in the
// vault tree. Enter opens the selected entry as a tab and dismisses.
//
// Triggered from File > Quick Switcher (⌘P) which flips
// `appState.showQuickSwitcher`; ContentView hosts the sheet.
struct QuickSwitcherSheet: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vault: VaultStore
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var queryFocused: Bool

    private static let resultLimit = 50

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find a note by name…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($queryFocused)
                    .onSubmit { openSelected() }
                    .onChange(of: query) { _, _ in selectedIndex = 0 }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            results
                .frame(maxHeight: 360)
        }
        .frame(width: 520)
        .background(.regularMaterial)
        .onAppear { queryFocused = true }
        .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    @ViewBuilder
    private var results: some View {
        let items = filteredResults
        if items.isEmpty {
            VStack(spacing: 4) {
                Text(query.isEmpty ? "No recent files" : "No matches")
                    .foregroundStyle(.secondary)
                if !query.isEmpty {
                    Text(query)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 30)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            row(item, isSelected: idx == selectedIndex)
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedIndex = idx
                                    openSelected()
                                }
                        }
                    }
                }
                .onChange(of: selectedIndex) { _, new in
                    if new < items.count {
                        proxy.scrollTo(items[new].id, anchor: .center)
                    }
                }
            }
        }
    }

    private func row(_ item: SwitcherItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.iconName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if item.isRecent {
                Text("Recent")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    // MARK: - Matching

    private struct SwitcherItem: Identifiable, Hashable {
        let relativePath: String
        let title: String
        let subtitle: String?
        let isRecent: Bool
        let iconName: String
        var id: String { relativePath }
    }

    private var filteredResults: [SwitcherItem] {
        let flat = flatten(tree: vault.tree)
        let pathToFlat = Dictionary(uniqueKeysWithValues: flat.map { ($0.relativePath, $0) })

        if query.isEmpty {
            // Recents first, then any remaining files (up to limit).
            let recentItems: [SwitcherItem] = appState.recentVaultFiles.compactMap { entry in
                guard let node = pathToFlat[entry.relativePath] else { return nil }
                return SwitcherItem(
                    relativePath: node.relativePath,
                    title: entry.title.isEmpty ? node.name : entry.title,
                    subtitle: node.parentPath,
                    isRecent: true,
                    iconName: node.iconName
                )
            }
            let recentSet = Set(recentItems.map(\.relativePath))
            let extras: [SwitcherItem] = flat
                .filter { !recentSet.contains($0.relativePath) }
                .prefix(Self.resultLimit - recentItems.count)
                .map { node in
                    SwitcherItem(
                        relativePath: node.relativePath,
                        title: node.name,
                        subtitle: node.parentPath,
                        isRecent: false,
                        iconName: node.iconName
                    )
                }
            return Array((recentItems + extras).prefix(Self.resultLimit))
        }

        let q = query.lowercased()
        let scored: [(Int, FlatNode)] = flat.compactMap { node in
            let nameLower = node.name.lowercased()
            let pathLower = node.relativePath.lowercased()
            if nameLower == q { return (0, node) }
            if nameLower.hasPrefix(q) { return (1, node) }
            if nameLower.contains(q) { return (2, node) }
            if pathLower.contains(q) { return (3, node) }
            if subsequenceMatch(q, in: nameLower) { return (4, node) }
            return nil
        }
        return scored
            .sorted { $0.0 < $1.0 }
            .prefix(Self.resultLimit)
            .map { (_, node) in
                SwitcherItem(
                    relativePath: node.relativePath,
                    title: node.name,
                    subtitle: node.parentPath,
                    isRecent: false,
                    iconName: node.iconName
                )
            }
    }

    private struct FlatNode {
        let relativePath: String
        let name: String
        let parentPath: String?
        let iconName: String
    }

    private func flatten(tree: FolderNode) -> [FlatNode] {
        var out: [FlatNode] = []
        out.reserveCapacity(256)
        walk(tree, into: &out)
        return out
    }

    private func walk(_ node: FolderNode, into out: inout [FlatNode]) {
        for child in node.children {
            if child.isDirectory {
                walk(child, into: &out)
            } else {
                let parent = (child.relativePath as NSString).deletingLastPathComponent
                out.append(FlatNode(
                    relativePath: child.relativePath,
                    name: child.name,
                    parentPath: parent.isEmpty ? nil : parent,
                    iconName: iconFor(name: child.name)
                ))
            }
        }
    }

    private func iconFor(name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == "md" || ext == "txt" { return "doc.text" }
        if ext == "pdf" { return "doc.richtext" }
        if ext == "epub" { return "book.closed" }
        if VaultStore.imageExts.contains(ext) { return "photo" }
        return "doc"
    }

    /// Cheap fuzzy match: every char of `needle` appears in `haystack` in order.
    private func subsequenceMatch(_ needle: String, in haystack: String) -> Bool {
        var hIdx = haystack.startIndex
        for ch in needle {
            guard let found = haystack[hIdx...].firstIndex(of: ch) else { return false }
            hIdx = haystack.index(after: found)
        }
        return true
    }

    // MARK: - Navigation

    private func moveSelection(by delta: Int) {
        let items = filteredResults
        guard !items.isEmpty else { return }
        let next = selectedIndex + delta
        selectedIndex = max(0, min(items.count - 1, next))
    }

    private func openSelected() {
        let items = filteredResults
        guard selectedIndex < items.count else { return }
        let item = items[selectedIndex]
        guard let url = vault.url(for: item.relativePath) else { return }
        let ext = (item.relativePath as NSString).pathExtension.lowercased()
        let title = (item.title as NSString).deletingPathExtension
        let isBinary = ext == "pdf" || ext == "epub" || VaultStore.imageExts.contains(ext)
        appState.openVaultFile(relativePath: item.relativePath) {
            let content = isBinary
                ? ""
                : (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let fileType = FileType.from(url: url)
            return TextDocument(title: title, content: content, fileType: fileType)
        }
        appState.selectedSidebarPath = item.relativePath
        dismiss()
    }
}
