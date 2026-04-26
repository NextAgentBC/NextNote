import SwiftUI

extension AssetLibraryView {
    @ViewBuilder
    var content: some View {
        ZStack {
            if filteredAssets.isEmpty {
                emptyState
            } else {
                grid
            }

            if isDropTargeting {
                dropHighlight
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            isDropTargeting = false
            importURLs(urls)
            return !urls.isEmpty
        } isTargeted: { active in
            isDropTargeting = active
        }
    }

    var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(filteredAssets) { asset in
                    AssetCell(asset: asset)
                        // Single-click opens preview — video cells surface
                        // the trim editor, audio plays inline, images get a
                        // full-size viewer. SwiftUI gives drag-gesture
                        // priority on click+drag, so cells stay draggable.
                        .onTapGesture { previewAsset = asset }
                        .contextMenu {
                            Button("Preview") { previewAsset = asset }
                            Button("Reveal in Finder") { revealInFinder(asset) }
                            Divider()
                            Button("Copy Markdown Embed") {
                                copyEmbedMarkdown(asset)
                            }
                            Menu("Move to") {
                                ForEach(sidebarFolderList, id: \.self) { name in
                                    Button(name) {
                                        moveAssets(urls: [asset.url], to: name)
                                    }
                                }
                                Divider()
                                Button("Root (loose)") {
                                    moveAssets(urls: [asset.url], to: "")
                                }
                            }
                            Divider()
                            Button("Move to Trash", role: .destructive) {
                                deleteTarget = asset
                            }
                        }
                        // URL is the simplest Transferable form. Works for
                        // both the editor (inserts Markdown embed) and the
                        // folder sidebar (moves the file between folders).
                        .draggable(asset.url) {
                            AssetCell(asset: asset)
                                .frame(width: 160)
                        }
                }
            }
            .padding(14)
        }
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "Drop files here" : "No matches")
                .font(.title3)
                .foregroundStyle(.secondary)
            if searchText.isEmpty {
                Text("Drag images, videos, and audio from Finder — or click Import.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.accentColor, lineWidth: 3)
            .padding(8)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    var filteredAssets: [AssetCatalog.Asset] {
        let base = assetCatalog.filtered(kind: kindFilter.mediaKind, folder: folderFilter)
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { $0.title.lowercased().contains(q) }
    }
}
