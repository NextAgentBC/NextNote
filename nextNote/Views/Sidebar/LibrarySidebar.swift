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

    /// Collapsible tray for the 素材库 / Asset Library. Header opens the
    /// full grid view (⌘⇧A). Expanded body lists recent files inline so
    /// the user can drag items directly into a note without opening the
    /// sheet every time.
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

                // "Open library" shortcut on the header — power users don't
                // have to dig through the Media menu to get to the grid.
                Button {
                    appState.showAssetLibrary = true
                } label: {
                    Image(systemName: "rectangle.grid.2x2")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Asset Library (⌘⇧A)")
                .padding(.trailing, 10)
            }
            .background(Color.secondary.opacity(0.05))

            if assetsExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let recent = Array(assetCatalog.assets.prefix(12))
                        if recent.isEmpty {
                            emptyHint("Open the Asset Library (⌘⇧A) and drop images, videos, or audio.")
                        } else {
                            ForEach(recent) { asset in
                                assetRow(asset)
                            }
                            if assetCatalog.assets.count > recent.count {
                                Button {
                                    appState.showAssetLibrary = true
                                } label: {
                                    Text("View all \(assetCatalog.assets.count) →")
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                        .padding(.vertical, 4)
                                        .padding(.leading, 14)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .task {
            _ = libraryRoots.ensureAssetsRoot()
            await assetCatalog.scan(root: libraryRoots.assetsRoot)
        }
        .onReceive(libraryRoots.$assetsRoot) { url in
            Task { await assetCatalog.scan(root: url) }
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
        .onTapGesture(count: 2) {
            appState.showAssetLibrary = true
        }
        .draggable(asset.url)
        .contextMenu {
            Button("Open in Library") { appState.showAssetLibrary = true }
            Button("Reveal in Finder") {
                #if os(macOS)
                NSWorkspace.shared.activateFileViewerSelecting([asset.url])
                #endif
            }
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
        .contextMenu {
            Button("Play") { playFile(item) }
            Button("Enqueue") { enqueueFile(item) }
            Divider()
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
