import SwiftUI
import SwiftData

// Top: Notes tree (flex — dominant). Bottom: two collapsible trays
// for Ebooks and Media. Single-vault per category, fixed; no per-section
// `+` UI clutter. Users change a root via menu or by deleting the
// UserDefaults bookmark.
struct LibrarySidebar: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var libraryRoots: LibraryRoots
    @EnvironmentObject private var mediaCatalog: MediaCatalog
    @EnvironmentObject private var assetCatalog: AssetCatalog
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Book.title) private var books: [Book]

    @State private var ebooksExpanded = true
    @State private var mediaExpanded = true
    @State private var assetsExpanded = true
    @State private var expandedFolders: Set<String> = []
    @State private var collapsedAssetFolders: Set<String> = []
    @State private var showNewAssetFolderAlert = false
    @State private var newAssetFolderName = ""
    @State private var assetDeleteTarget: AssetCatalog.Asset?
    @State private var assetError: String?
    /// Key of the folder-group row currently being hovered by a drag — used
    /// to tint the header so the user sees the drop target.
    @State private var hoveredDropTarget: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            NotesSection()
                .frame(maxHeight: .infinity)

            // Trays share one scrollable region so a short window doesn't
            // clip the last tray off-screen (previous bug: Assets was
            // invisible on default window heights because Ebooks + Media
            // together exceeded the bottom half).
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    assetsTray
                    Divider()
                    ebooksTray
                    Divider()
                    mediaTray
                }
            }
            .frame(maxHeight: 420)
        }
        .onChange(of: appState.triggerRescanLibrary) { _, v in
            if v {
                appState.triggerRescanLibrary = false
            }
        }
        .alert("New Asset Folder", isPresented: $showNewAssetFolderAlert) {
            TextField("Name", text: $newAssetFolderName)
            Button("Cancel", role: .cancel) { newAssetFolderName = "" }
            Button("Create") { createAssetFolder() }
        }
        .alert("Move Asset to Trash?", isPresented: .init(
            get: { assetDeleteTarget != nil },
            set: { if !$0 { assetDeleteTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                if let asset = assetDeleteTarget {
                    trashAsset(asset)
                }
                assetDeleteTarget = nil
            }
        } message: {
            Text(assetDeleteTarget?.title ?? "")
        }
        .alert("Asset Error", isPresented: .init(
            get: { assetError != nil },
            set: { if !$0 { assetError = nil } }
        )) {
            Button("OK") { assetError = nil }
        } message: {
            Text(assetError ?? "")
        }
    }

    // MARK: - Ebooks

    private var ebooksTray: some View {
        VStack(alignment: .leading, spacing: 0) {
            trayHeader(
                title: "Ebooks",
                icon: "books.vertical",
                count: books.count,
                expanded: $ebooksExpanded
            )
            if ebooksExpanded {
                ScrollView {
                    BooksSection(books: books)
                }
                .frame(maxHeight: 260)
            }
        }
    }

    // MARK: - Assets

    @State private var assetsDropTargeted: Bool = false

    /// Collapsible tray for the 素材库 / Asset Library. The sidebar is the
    /// primary workflow: folders, row actions, drag into notes, and main-area
    /// preview all happen here without sending the user to a separate sheet.
    ///
    /// The whole tray is a drop destination — users can drag files from
    /// Finder or from the Media tray (sidebar rows are `.draggable(URL)`)
    /// onto it to copy them into the Assets root.
    private var assetsTray: some View {
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
                .frame(maxHeight: 260)
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
    private func importToAssets(_ urls: [URL]) -> Bool {
        guard let root = libraryRoots.ensureAssetsRoot() else { return false }
        let fm = FileManager.default
        var imported = 0
        for src in urls {
            guard let kind = MediaKind.from(url: src) else { continue }
            let bucket: String
            switch kind {
            case .image: bucket = "images"
            case .video: bucket = "videos"
            case .audio: bucket = "audio"
            }
            let dir = root.appendingPathComponent(bucket, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = uniqueAssetsDestination(for: src.lastPathComponent, in: dir)
            do {
                try fm.copyItem(at: src, to: dest)
                imported += 1
            } catch {
                // Silent — drop UI doesn't have error surface. Skipped
                // files just won't appear.
            }
        }
        guard imported > 0 else { return false }
        Task { await assetCatalog.scan(root: libraryRoots.assetsRoot) }
        return true
    }

    private func uniqueAssetsDestination(for filename: String, in dir: URL) -> URL {
        let fm = FileManager.default
        let url = dir.appendingPathComponent(filename)
        if !fm.fileExists(atPath: url.path) { return url }
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        for n in 2... {
            let candidate = dir.appendingPathComponent("\(stem)-\(n).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    private struct AssetFolderGroup: Identifiable {
        let id: String
        let folder: String
        let title: String
        let assets: [AssetCatalog.Asset]
    }

    private var assetFolderGroups: [AssetFolderGroup] {
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
    private func assetFolderRow(_ group: AssetFolderGroup) -> some View {
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
    private func assetRow(_ asset: AssetCatalog.Asset) -> some View {
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

    private var assetMoveFolders: [String] {
        var folders = Set(assetCatalog.folders)
        folders.formUnion(assetCatalog.assets.map(\.folder).filter { !$0.isEmpty })
        return [""] + folders.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func openAssetInMain(_ asset: AssetCatalog.Asset) {
        appState.openExternalMedia(url: asset.url, title: asset.title)
    }

    private func copyAssetMarkdown(_ asset: AssetCatalog.Asset) {
        let markdown = "![\(asset.title)](\(asset.url.absoluteString))"
        copyToPasteboard(markdown)
    }

    private func copyAssetFileURL(_ asset: AssetCatalog.Asset) {
        copyToPasteboard(asset.url.absoluteString)
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func createAssetFolder() {
        let raw = newAssetFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newAssetFolderName = ""
        guard !raw.isEmpty else { return }
        let name = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard let root = libraryRoots.ensureAssetsRoot() else { return }
        do {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            collapsedAssetFolders.remove("asset/\(name)")
            Task { await assetCatalog.scan(root: libraryRoots.assetsRoot) }
        } catch {
            assetError = "Create folder failed: \(error.localizedDescription)"
        }
    }

    private func moveOrImportAssets(_ urls: [URL], to folder: String) -> Bool {
        guard let root = libraryRoots.ensureAssetsRoot() else { return false }
        let destination = assetFolderURL(folder) ?? root
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            assetError = "Move failed: \(error.localizedDescription)"
            return false
        }

        var changed = 0
        for src in urls {
            guard MediaKind.from(url: src) != nil else { continue }
            let dest = uniqueAssetsDestination(for: src.lastPathComponent, in: destination)
            do {
                if isAssetURL(src, under: root) {
                    let srcDir = src.deletingLastPathComponent().standardizedFileURL.path
                    guard srcDir != destination.standardizedFileURL.path else { continue }
                    try FileManager.default.moveItem(at: src, to: dest)
                } else {
                    try FileManager.default.copyItem(at: src, to: dest)
                }
                changed += 1
            } catch {
                assetError = "Move failed: \(error.localizedDescription)"
                return false
            }
        }
        guard changed > 0 else { return false }
        Task { await assetCatalog.scan(root: libraryRoots.assetsRoot) }
        return true
    }

    private func assetFolderURL(_ folder: String) -> URL? {
        guard let root = libraryRoots.assetsRoot else { return nil }
        return folder.isEmpty ? root : root.appendingPathComponent(folder, isDirectory: true)
    }

    private func isAssetURL(_ url: URL, under root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        return url.standardizedFileURL.path.hasPrefix(rootPath + "/")
    }

    private func revealAssetFolder(_ folder: String?) {
        #if os(macOS)
        let url: URL?
        if let folder {
            url = assetFolderURL(folder)
        } else {
            url = libraryRoots.assetsRoot
        }
        if let url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        #endif
    }

    private func revealAsset(_ asset: AssetCatalog.Asset) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([asset.url])
        #endif
    }

    private func trashAsset(_ asset: AssetCatalog.Asset) {
        do {
            try FileManager.default.trashItem(at: asset.url, resultingItemURL: nil)
            Task { await assetCatalog.scan(root: libraryRoots.assetsRoot) }
        } catch {
            assetError = "Move to Trash failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Media

    private var mediaTray: some View {
        let totalMedia = mediaCatalog.music.count + mediaCatalog.videos.count
        return VStack(alignment: .leading, spacing: 0) {
            trayHeader(
                title: "Media",
                icon: "play.square.stack",
                count: totalMedia,
                expanded: $mediaExpanded
            )
            if mediaExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let musicGroups = mediaCatalog.musicGroups
                        let videoGroups = mediaCatalog.videoGroups
                        if !musicGroups.isEmpty {
                            subHeader(title: "Music")
                            ForEach(musicGroups) { group in
                                folderGroup(group, kindKey: "music") {
                                    AmbientPlayer.shared.playURL($0.url, title: $0.title)
                                }
                            }
                        }
                        if !videoGroups.isEmpty {
                            subHeader(title: "Videos")
                            ForEach(videoGroups) { group in
                                folderGroup(group, kindKey: "video") {
                                    AmbientPlayer.shared.playURL($0.url, title: $0.title)
                                }
                            }
                        }
                        if totalMedia == 0 {
                            emptyHint(
                                "Drop files into \(friendlyPath(libraryRoots.mediaRoot))."
                            )
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func trayHeader(
        title: String,
        icon: String,
        count: Int,
        expanded: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { expanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                if count > 0 {
                    Text("\(count)")
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
        .background(Color.secondary.opacity(0.05))
    }

    private func subHeader(title: String) -> some View {
        Text(title)
            .font(.caption2.bold())
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func folderGroup(
        _ group: MediaCatalog.MediaGroup,
        kindKey: String,
        onTap: @escaping (MediaCatalog.MediaFile) -> Void
    ) -> some View {
        let key = "\(kindKey)/\(group.folder)"
        let expanded = expandedFolders.contains(key)
        let title = group.folder.isEmpty ? "Loose files" : group.folder
        let folderURL = folderURL(for: group)
        let isDropTarget = hoveredDropTarget == key

        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                if expanded { expandedFolders.remove(key) }
                else { expandedFolders.insert(key) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("\(group.items.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.vertical, 3)
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .background(isDropTarget ? Color.accentColor.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(folderURL ?? URL(fileURLWithPath: "/"))
        .dropDestination(for: URL.self) { urls, _ in
            guard let src = urls.first, let dst = folderURL else { return false }
            return mergeFolder(source: src, target: dst)
        } isTargeted: { active in
            hoveredDropTarget = active ? key : (hoveredDropTarget == key ? nil : hoveredDropTarget)
        }
        .contextMenu {
            Button("Play All") { playGroup(group, shuffle: false) }
                .disabled(group.items.isEmpty)
            Button("Play Shuffled") { playGroup(group, shuffle: true) }
                .disabled(group.items.isEmpty)
            Button("Enqueue") { enqueueGroup(group) }
                .disabled(group.items.isEmpty)
            Divider()
            Button("Reveal in Finder") {
                #if os(macOS)
                if let url = folderURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                #endif
            }
            .disabled(folderURL == nil)
        }

        if expanded {
            ForEach(group.items) { item in
                mediaRow(item, indent: 30, action: { onTap(item) })
            }
        }
    }

    // MARK: - Play helpers

    private func tracks(from group: MediaCatalog.MediaGroup) -> [Track] {
        group.items.map {
            Track(id: UUID(), url: $0.url, title: $0.title, bookmark: nil)
        }
    }

    /// Queue every file under `group` and start playback. Pop the video
    /// window when any item is video so the user sees the picture.
    private func playGroup(_ group: MediaCatalog.MediaGroup, shuffle: Bool) {
        var list = tracks(from: group)
        guard !list.isEmpty else { return }
        if shuffle { list.shuffle() }
        AmbientPlayer.shared.setQueue(list)
        if list.contains(where: { MediaKind.from(url: $0.url) == .video }) {
            VideoVibeWindowController.shared.show()
        }
    }

    private func enqueueGroup(_ group: MediaCatalog.MediaGroup) {
        let list = tracks(from: group)
        guard !list.isEmpty else { return }
        AmbientPlayer.shared.enqueue(list)
        if list.contains(where: { MediaKind.from(url: $0.url) == .video }) {
            VideoVibeWindowController.shared.show()
        }
    }

    private func playFile(_ item: MediaCatalog.MediaFile) {
        AmbientPlayer.shared.playURL(item.url, title: item.title)
        if MediaKind.from(url: item.url) == .video {
            VideoVibeWindowController.shared.show()
        }
    }

    private func enqueueFile(_ item: MediaCatalog.MediaFile) {
        let t = Track(id: UUID(), url: item.url, title: item.title, bookmark: nil)
        AmbientPlayer.shared.enqueue([t])
        if MediaKind.from(url: item.url) == .video {
            VideoVibeWindowController.shared.show()
        }
    }

    private func folderURL(for group: MediaCatalog.MediaGroup) -> URL? {
        guard let root = libraryRoots.mediaRoot, !group.folder.isEmpty else { return nil }
        return root.appendingPathComponent(group.folder, isDirectory: true)
    }

    /// Run a folder-into-folder merge triggered by a sidebar drag-drop.
    /// Returns true on success so SwiftUI finalizes the drop animation.
    private func mergeFolder(source: URL, target: URL) -> Bool {
        let srcStd = source.standardizedFileURL.path
        let tgtStd = target.standardizedFileURL.path
        if srcStd == tgtStd { return false }
        // Only accept drags from within the media root — don't treat a
        // random Finder drop as a merge.
        guard let root = libraryRoots.mediaRoot?.standardizedFileURL.path,
              srcStd.hasPrefix(root), tgtStd.hasPrefix(root)
        else { return false }
        do {
            _ = try MediaFolderMerger.merge(source: source, into: target)
            Task { await mediaCatalog.scan(mediaRoot: libraryRoots.mediaRoot) }
            return true
        } catch {
            return false
        }
    }

    @ViewBuilder
    private func mediaRow(
        _ item: MediaCatalog.MediaFile,
        indent: CGFloat = 22,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.kind.iconName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.leading, indent)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        // Dragging a media row carries its file URL, so it can be dropped
        // onto the Assets tray (to copy into the asset library) or into
        // the markdown editor (to embed via `![](path)`).
        .draggable(item.url)
        .contextMenu {
            Button("Play") { playFile(item) }
            Button("Enqueue") { enqueueFile(item) }
            Divider()
            Button("Add to Assets") { _ = importToAssets([item.url]) }
            Button("Reveal in Finder") {
                #if os(macOS)
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                #endif
            }
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func friendlyPath(_ url: URL?) -> String {
        guard let url else { return "the Media folder" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
