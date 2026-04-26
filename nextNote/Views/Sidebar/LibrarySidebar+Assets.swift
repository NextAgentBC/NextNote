import SwiftUI

extension LibrarySidebar {
    /// Collapsible tray for the Asset Library. The sidebar is the primary
    /// workflow: folders, row actions, drag into notes, and main-area
    /// preview all happen here without sending the user to a separate sheet.
    ///
    /// The whole tray is a drop destination — users can drag files from
    /// Finder or from the Media tray (sidebar rows are `.draggable(URL)`)
    /// onto it to copy them into the Assets root.
    var assetsTray: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        assetsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: assetsExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        Image(systemName: "photo.stack")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Assets")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        if assetCatalog.assets.count > 0 {
                            Text("\(assetCatalog.assets.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    newAssetFolderName = ""
                    showNewAssetFolderAlert = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Asset Folder")
                .padding(.trailing, 10)
            }
            .background(Color.secondary.opacity(0.05))
            .contextMenu {
                Button("New Folder") {
                    newAssetFolderName = ""
                    showNewAssetFolderAlert = true
                }
                Button("Reveal Assets Folder") {
                    revealAssetFolder(nil)
                }
            }

            if assetsExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let groups = assetFolderGroups
                        if groups.isEmpty {
                            emptyHint("Drop images, videos, or audio here.")
                        } else {
                            ForEach(groups) { group in
                                assetFolderRow(group)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .task {
            _ = libraryRoots.ensureAssetsRoot()
            await assetCatalog.scan(root: libraryRoots.assetsRoot)
        }
        .onReceive(libraryRoots.$assetsRoot) { url in
            Task { await assetCatalog.scan(root: url) }
        }
        .background(assetsDropTargeted ? Color.accentColor.opacity(0.12) : .clear)
        .dropDestination(for: URL.self) { urls, _ in
            assetsDropTargeted = false
            return importToAssets(urls)
        } isTargeted: { active in
            assetsDropTargeted = active
        }
    }

    /// Copy dropped files into the Assets root, auto-routed by kind into
    /// the default subfolders (images/videos/audio). Accepts drops from
    /// Finder and from the Media sidebar rows.
    func importToAssets(_ urls: [URL]) -> Bool {
        guard let root = libraryRoots.ensureAssetsRoot() else { return false }
        var imported = 0
        for src in urls {
            guard let kind = MediaKind.from(url: src) else { continue }
            let dir = AssetLibraryActions.bucketDirectory(for: kind, root: root)
            imported += AssetLibraryActions.importByCopy([src], to: dir)
        }
        guard imported > 0 else { return false }
        Task { await assetCatalog.scan(root: libraryRoots.assetsRoot) }
        return true
    }

    var assetFolderGroups: [AssetFolderGroup] {
        let grouped = Dictionary(grouping: assetCatalog.assets, by: { $0.folder })
        let defaultFolders = Set(LibraryRoots.defaultAssetSubfolders)
        var folders = Set(assetCatalog.folders)
        folders.formUnion(grouped.keys.filter { !$0.isEmpty })

        var out: [AssetFolderGroup] = []
        if let loose = grouped[""], !loose.isEmpty {
            out.append(.init(id: "asset/loose", folder: "", title: "Loose", assets: loose))
        }
        for name in folders.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            guard !name.isEmpty else { continue }
            let items = grouped[name] ?? []
            if items.isEmpty && defaultFolders.contains(name) { continue }
            out.append(.init(id: "asset/\(name)", folder: name, title: name, assets: items))
        }
        return out
    }

    @ViewBuilder
    func assetFolderRow(_ group: AssetFolderGroup) -> some View {
        let collapsed = collapsedAssetFolders.contains(group.id)
        let folderURL = assetFolderURL(group.folder)
        let isDropTarget = hoveredDropTarget == group.id

        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                if collapsed { collapsedAssetFolders.remove(group.id) }
                else { collapsedAssetFolders.insert(group.id) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Image(systemName: group.folder.isEmpty ? "square.dashed" : "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(group.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if !group.assets.isEmpty {
                    Text("\(group.assets.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .background(isDropTarget ? Color.accentColor.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropDestination(for: URL.self) { urls, _ in
            hoveredDropTarget = nil
            return moveOrImportAssets(urls, to: group.folder)
        } isTargeted: { active in
            hoveredDropTarget = active ? group.id : (hoveredDropTarget == group.id ? nil : hoveredDropTarget)
        }
        .contextMenu {
            Button("New Folder") {
                newAssetFolderName = ""
                showNewAssetFolderAlert = true
            }
            Button("Reveal in Finder") {
                revealAssetFolder(group.folder)
            }
            .disabled(folderURL == nil)
        }

        if !collapsed {
            ForEach(group.assets) { asset in
                assetRow(asset)
            }
        }
    }

    /// Single-line row inside the Assets tray. Draggable so the user can
    /// pull it into a markdown note without opening the full library.
    @ViewBuilder
    func assetRow(_ asset: AssetCatalog.Asset) -> some View {
        HStack(spacing: 6) {
            Image(systemName: asset.kind.iconName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(asset.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.leading, 26)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            openAssetInMain(asset)
        }
        .draggable(asset.url)
        .contextMenu {
            Button(asset.kind == .video ? "Open / Trim" : "Open") {
                openAssetInMain(asset)
            }
            Divider()
            Button("Copy Markdown Embed") { copyAssetMarkdown(asset) }
            Button("Copy File URL") { copyAssetFileURL(asset) }
            Menu("Move to") {
                ForEach(assetMoveFolders, id: \.self) { folder in
                    Button(folder.isEmpty ? "Loose" : folder) {
                        _ = moveOrImportAssets([asset.url], to: folder)
                    }
                    .disabled(asset.folder == folder)
                }
            }
            Divider()
            Button("Reveal in Finder") {
                revealAsset(asset)
            }
            Button("Move to Trash", role: .destructive) {
                assetDeleteTarget = asset
            }
        }
    }

    var assetMoveFolders: [String] {
        var folders = Set(assetCatalog.folders)
        folders.formUnion(assetCatalog.assets.map(\.folder).filter { !$0.isEmpty })
        return [""] + folders.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func openAssetInMain(_ asset: AssetCatalog.Asset) {
        appState.openExternalMedia(url: asset.url, title: asset.title)
    }

    func copyAssetMarkdown(_ asset: AssetCatalog.Asset) {
        PasteboardActions.copyMarkdownEmbed(title: asset.title, path: asset.url.absoluteString)
    }

    func copyAssetFileURL(_ asset: AssetCatalog.Asset) {
        PasteboardActions.copy(asset.url.absoluteString)
    }

    func createAssetFolder() {
        let raw = newAssetFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newAssetFolderName = ""
        guard !raw.isEmpty else { return }
        guard let root = libraryRoots.ensureAssetsRoot() else { return }
        do {
            let dir = try AssetLibraryActions.createFolder(named: raw, under: root)
            collapsedAssetFolders.remove("asset/\(dir.lastPathComponent)")
            Task { await assetCatalog.scan(root: libraryRoots.assetsRoot) }
        } catch {
            assetError = "Create folder failed: \(error.localizedDescription)"
        }
    }

    func moveOrImportAssets(_ urls: [URL], to folder: String) -> Bool {
        guard let root = libraryRoots.ensureAssetsRoot() else { return false }
        let destination = assetFolderURL(folder) ?? root
        do {
            let changed = try AssetLibraryActions.moveOrImport(urls, to: destination, root: root)
            guard changed > 0 else { return false }
            Task { await assetCatalog.scan(root: libraryRoots.assetsRoot) }
            return true
        } catch {
            assetError = "Move failed: \(error.localizedDescription)"
            return false
        }
    }

    func assetFolderURL(_ folder: String) -> URL? {
        guard let root = libraryRoots.assetsRoot else { return nil }
        return folder.isEmpty ? root : root.appendingPathComponent(folder, isDirectory: true)
    }

    func revealAssetFolder(_ folder: String?) {
        if let folder {
            FinderActions.reveal(assetFolderURL(folder))
        } else {
            FinderActions.reveal(libraryRoots.assetsRoot)
        }
    }

    func revealAsset(_ asset: AssetCatalog.Asset) {
        FinderActions.reveal(asset.url)
    }

    func trashAsset(_ asset: AssetCatalog.Asset) {
        do {
            try FileManager.default.trashItem(at: asset.url, resultingItemURL: nil)
            Task { await assetCatalog.scan(root: libraryRoots.assetsRoot) }
        } catch {
            assetError = "Move to Trash failed: \(error.localizedDescription)"
        }
    }
}
