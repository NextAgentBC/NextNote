import SwiftUI

extension LibrarySidebar {
    var mediaTray: some View {
        let musicGroups = mediaLibrary.groups(kind: .audio, under: libraryRoots.mediaRoot)
        let videoGroups = mediaLibrary.groups(kind: .video, under: libraryRoots.mediaRoot)
        let totalMedia = musicGroups.reduce(0) { $0 + $1.items.count }
            + videoGroups.reduce(0) { $0 + $1.items.count }
        return VStack(alignment: .leading, spacing: 0) {
            trayHeader(
                title: "Media",
                icon: "play.square.stack",
                count: totalMedia,
                expanded: $mediaExpanded
            )
            .contextMenu {
                Button("Rescan Media Folder") {
                    Task { await mediaLibrary.scanRoot(libraryRoots.mediaRoot) }
                }
            }
            // Re-scan whenever the user re-expands the tray — covers the
            // common "I just moved files in Finder / via Tidy with Claude,
            // why doesn't it show" case without polling.
            .onChange(of: mediaExpanded) { _, isOpen in
                if isOpen {
                    Task { await mediaLibrary.scanRoot(libraryRoots.mediaRoot) }
                }
            }
            if mediaExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !musicGroups.isEmpty {
                            subHeader(title: "Music")
                            ForEach(musicGroups) { group in
                                folderGroup(group) { playFile($0) }
                            }
                        }
                        if !videoGroups.isEmpty {
                            subHeader(title: "Videos")
                            ForEach(videoGroups) { group in
                                folderGroup(group) { playFile($0) }
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

    @ViewBuilder
    func folderGroup(
        _ group: MediaLibrary.MediaGroup,
        onTap: @escaping (Track) -> Void
    ) -> some View {
        let key = group.id
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
                FinderActions.reveal(folderURL)
            }
            .disabled(folderURL == nil)
        }

        if expanded {
            ForEach(group.items) { item in
                mediaRow(item, indent: 30, action: { onTap(item) })
            }
        }
    }

    @ViewBuilder
    func mediaRow(
        _ track: Track,
        indent: CGFloat = 22,
        action: @escaping () -> Void
    ) -> some View {
        let kind = MediaKind.from(url: track.url) ?? .audio
        HStack(spacing: 6) {
            Image(systemName: kind.iconName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(track.title)
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
        .draggable(track.url)
        .contextMenu {
            Button("Play") { playFile(track) }
            Button("Enqueue") { enqueueFile(track) }
            Divider()
            Button("Add to Assets") { _ = importToAssets([track.url]) }
            Button("Reveal in Finder") {
                FinderActions.reveal(track.url)
            }
            Divider()
            Button("Remove from Library") {
                mediaLibrary.removeTrack(id: track.id)
            }
            Button("Move to Trash", role: .destructive) {
                _ = mediaLibrary.trashTrack(id: track.id)
            }
        }
    }

    /// Queue every file under `group` and start playback. Pop the video
    /// window when any item is video so the user sees the picture.
    func playGroup(_ group: MediaLibrary.MediaGroup, shuffle: Bool) {
        var list = group.items
        guard !list.isEmpty else { return }
        if shuffle { list.shuffle() }
        AmbientPlayer.shared.setQueue(list)
        if group.kind == .video {
            VideoVibeWindowController.shared.show()
        }
    }

    func enqueueGroup(_ group: MediaLibrary.MediaGroup) {
        let list = group.items
        guard !list.isEmpty else { return }
        AmbientPlayer.shared.enqueue(list)
        if group.kind == .video {
            VideoVibeWindowController.shared.show()
        }
    }

    func playFile(_ track: Track) {
        AmbientPlayer.shared.setQueue([track])
        if MediaKind.from(url: track.url) == .video {
            VideoVibeWindowController.shared.show()
        }
    }

    func enqueueFile(_ track: Track) {
        AmbientPlayer.shared.enqueue([track])
        if MediaKind.from(url: track.url) == .video {
            VideoVibeWindowController.shared.show()
        }
    }

    func folderURL(for group: MediaLibrary.MediaGroup) -> URL? {
        guard let root = libraryRoots.mediaRoot, !group.folder.isEmpty else { return nil }
        return root.appendingPathComponent(group.folder, isDirectory: true)
    }

    /// Run a folder-into-folder merge triggered by a sidebar drag-drop.
    /// Returns true on success so SwiftUI finalizes the drop animation.
    func mergeFolder(source: URL, target: URL) -> Bool {
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
            Task { await mediaLibrary.scanRoot(libraryRoots.mediaRoot) }
            return true
        } catch {
            return false
        }
    }
}
