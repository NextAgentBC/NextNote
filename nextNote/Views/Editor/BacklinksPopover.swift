import SwiftUI

// Status-bar pill that shows the backlinks count for the active vault note,
// expanding into a popover listing the source notes on click. Rebuild
// triggered on every open so the index reflects fresh edits without us
// having to subscribe to every save in the app.
struct BacklinksPill: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var backlinksIndex: BacklinksIndex

    @State private var showPopover = false

    var body: some View {
        if let relPath = activeVaultPath() {
            let count = backlinksIndex.backlinks(for: relPath).count
            Button {
                showPopover.toggle()
                if showPopover { Task { await refresh() } }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .medium))
                    Text(count > 0 ? "\(count)" : "—")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(count > 0 ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help(count > 0 ? "\(count) backlink(s)" : "No backlinks")
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                popoverBody(activePath: relPath)
            }
        } else {
            EmptyView()
        }
    }

    private func activeVaultPath() -> String? {
        guard let id = appState.activeTabId else { return nil }
        return appState.vaultPath(forTabId: id)
    }

    @ViewBuilder
    private func popoverBody(activePath: String) -> some View {
        let sources = backlinksIndex.backlinks(for: activePath)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Backlinks")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if backlinksIndex.isBuilding {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("Rebuild index")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if sources.isEmpty {
                Text(backlinksIndex.isBuilding ? "Scanning vault…" : "No notes link here yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sources, id: \.self) { path in
                            sourceRow(path)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .frame(width: 280)
    }

    private func sourceRow(_ path: String) -> some View {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let parent = (path as NSString).deletingLastPathComponent
        return Button {
            openSource(path: path)
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

    private func openSource(path: String) {
        guard let url = vault.url(for: path) else { return }
        let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        appState.openVaultFile(relativePath: path) {
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return TextDocument(title: title, content: content, fileType: .md)
        }
        appState.selectedSidebarPath = path
        showPopover = false
    }

    private func refresh() async {
        let mdPaths = collectMdPaths(in: vault.tree)
        await backlinksIndex.rebuild(root: vault.root, mdRelativePaths: mdPaths)
    }

    private func collectMdPaths(in node: FolderNode) -> [String] {
        var out: [String] = []
        out.reserveCapacity(128)
        walk(node, into: &out)
        return out
    }

    private func walk(_ node: FolderNode, into out: inout [String]) {
        for child in node.children {
            if child.isDirectory {
                walk(child, into: &out)
            } else if (child.name as NSString).pathExtension.lowercased() == "md" {
                out.append(child.relativePath)
            }
        }
    }
}
