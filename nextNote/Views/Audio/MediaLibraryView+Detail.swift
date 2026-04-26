import SwiftUI

extension MediaLibraryView {
    @ViewBuilder
    var detail: some View {
        if let pid = selectedPlaylistID, let playlist = library.playlists.first(where: { $0.id == pid }) {
            playlistDetail(playlist)
        } else {
            allTracksDetail
        }
    }

    var allTracksDetail: some View {
        let shown = filter(library.tracks)
        return VStack(spacing: 0) {
            detailHeader(title: "All Tracks", count: shown.count) {
                HStack(spacing: 8) {
                    Picker("", selection: $kindFilter) {
                        ForEach(KindFilter.allCases, id: \.self) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    Button {
                        importerOpen = true
                    } label: {
                        Label("Add Files…", systemImage: "plus")
                    }

                    Menu {
                        if library.playlists.isEmpty {
                            Text("No playlists — create one first.")
                        } else {
                            ForEach(library.playlists) { p in
                                Button(p.name) {
                                    library.addToPlaylist(p.id, trackIDs: Array(selectedTrackIDs))
                                }
                            }
                        }
                    } label: {
                        Label("Add to Playlist…", systemImage: "text.badge.plus")
                    }
                    .disabled(selectedTrackIDs.isEmpty)

                    Button {
                        let tracks = shown.filter { selectedTrackIDs.contains($0.id) }
                        if !tracks.isEmpty { playRouted(tracks) }
                    } label: {
                        Label("Play Selected", systemImage: "play.fill")
                    }
                    .disabled(selectedTrackIDs.isEmpty)

                    Button {
                        let tracks = shown.filter { selectedTrackIDs.contains($0.id) }
                        autoOrganize(tracks)
                    } label: {
                        Label("Auto-organize (AI)", systemImage: "sparkles")
                    }
                    .disabled(selectedTrackIDs.isEmpty || isOrganizing || locator.downloadFolderURL == nil)
                    .help(locator.downloadFolderURL == nil
                        ? "Set a download folder in the YouTube sheet first — organize moves files into it."
                        : "Ask the LLM to classify each file by title and move into Category/Subcategory subfolders.")
                }
            }

            if isOrganizing || !organizeStatus.isEmpty {
                HStack(spacing: 8) {
                    if isOrganizing { ProgressView().controlSize(.small) }
                    Text(organizeStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if !isOrganizing && !organizeStatus.isEmpty {
                        Button("Clear") { organizeStatus = "" }
                            .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            }

            Divider()

            trackTable(shown, onRemove: { id in
                library.removeTrack(id: id)
                selectedTrackIDs.remove(id)
            })
        }
    }

    func playlistDetail(_ playlist: Playlist) -> some View {
        let tracks = library.tracks(in: playlist)
        return VStack(spacing: 0) {
            detailHeader(title: playlist.name, count: tracks.count) {
                HStack(spacing: 8) {
                    Button {
                        playRouted(tracks)
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                    }
                    .disabled(tracks.isEmpty)

                    Button {
                        player.enqueue(tracks)
                        if tracks.contains(where: { MediaKind.from(url: $0.url) == .video }) {
                            VideoVibeWindowController.shared.show()
                        }
                    } label: {
                        Label("Enqueue", systemImage: "text.append")
                    }
                    .disabled(tracks.isEmpty)

                    Button(role: .destructive) {
                        let offsets = IndexSet(
                            tracks.enumerated()
                                .filter { selectedTrackIDs.contains($0.element.id) }
                                .map { $0.offset }
                        )
                        library.removeFromPlaylist(playlist.id, at: offsets)
                        selectedTrackIDs.removeAll()
                    } label: {
                        Label("Remove from Playlist", systemImage: "minus.circle")
                    }
                    .disabled(selectedTrackIDs.isEmpty)
                }
            }

            Divider()

            trackTable(tracks, onRemove: { id in
                if let idx = tracks.firstIndex(where: { $0.id == id }) {
                    library.removeFromPlaylist(playlist.id, at: IndexSet(integer: idx))
                }
                selectedTrackIDs.remove(id)
            })
        }
    }

    func detailHeader<Actions: View>(
        title: String,
        count: Int,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                Text("\(count) tracks").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            actions()
        }
        .padding(12)
    }

    func trackTable(_ tracks: [Track], onRemove: @escaping (UUID) -> Void) -> some View {
        Table(tracks, selection: $selectedTrackIDs) {
            TableColumn("Title") { t in
                HStack {
                    if player.currentIndex.flatMap({ player.queue.indices.contains($0) ? player.queue[$0] : nil })?.id == t.id {
                        Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(t.title)
                }
            }
            TableColumn("Path") { t in
                Text(t.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            TableColumn("Kind") { t in
                Image(systemName: MediaKind.from(url: t.url) == .video ? "play.rectangle" : "music.note")
                    .foregroundStyle(.secondary)
            }
            .width(40)

            TableColumn("") { t in
                HStack(spacing: 4) {
                    Button {
                        playRouted([t])
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        onRemove(t.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove from Library (file stays on disk)")
                }
            }
            .width(60)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if !ids.isEmpty {
                if ids.count == 1, let id = ids.first, let t = tracks.first(where: { $0.id == id }) {
                    Button("Rename Title…") { beginRenameTrack(t, kind: .title) }
                    Button("Rename File on Disk…") { beginRenameTrack(t, kind: .file) }
                    Divider()
                }
                Button("Remove from Library") {
                    for id in ids { library.removeTrack(id: id) }
                    selectedTrackIDs.subtract(ids)
                }
                Button("Move Files to Trash", role: .destructive) {
                    for id in ids { _ = library.trashTrack(id: id) }
                    selectedTrackIDs.subtract(ids)
                }
                Divider()
                Button("Reveal in Finder") {
                    let urls = tracks.filter { ids.contains($0.id) }.map { $0.url }
                    FinderActions.reveal(urls)
                }
            }
        }
    }
}
