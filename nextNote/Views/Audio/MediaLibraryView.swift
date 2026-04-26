import SwiftUI
import UniformTypeIdentifiers

// Full media manager: browse all known tracks, build named playlists, queue
// them into the ambient player. Opened as a sheet from AmbientBar or via
// the Cmd+Shift+M keyboard shortcut.
struct MediaLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var library = MediaLibrary.shared
    @StateObject private var player = AmbientPlayer.shared
    @StateObject private var locator = YTDLPLocator.shared

    @State private var isOrganizing: Bool = false
    @State private var organizeStatus: String = ""
    @State private var isGeneratingPlaylists: Bool = false
    @State private var playlistGenStatus: String = ""

    // Sidebar selection: either "All Tracks" (nil) or a specific playlist ID.
    @State private var selectedPlaylistID: UUID? = nil
    @State private var selectedTrackIDs: Set<UUID> = []
    @State private var newPlaylistName: String = ""
    @State private var showingNewPlaylist: Bool = false
    @State private var renameTarget: Playlist? = nil
    @State private var renameText: String = ""
    @State private var importerOpen: Bool = false
    @State private var kindFilter: KindFilter = .all
    @State private var isBackfilling: Bool = false
    @State private var backfillStatus: String = ""
    @State private var isAutoCleaning: Bool = false
    @State private var autoCleanStatus: String = ""
    // Track rename flow — nil when hidden. `renameTrackKind` distinguishes
    // "title only" from "file on disk" so we can reuse one alert for both.
    @State private var renameTrackTarget: Track?
    @State private var renameTrackText: String = ""
    @State private var renameTrackKind: TrackRenameKind = .title
    @State private var renameTrackError: String?

    enum TrackRenameKind { case title, file }

    enum KindFilter: String, CaseIterable {
        case all = "All"
        case audio = "Audio"
        case video = "Video"
    }

    private func filter(_ tracks: [Track]) -> [Track] {
        switch kindFilter {
        case .all: return tracks
        case .audio: return tracks.filter { MediaKind.from(url: $0.url) == .audio }
        case .video: return tracks.filter { MediaKind.from(url: $0.url) == .video }
        }
    }

    /// Hand tracks off to the unified player. If the batch contains any
    /// video, also open the pop-out window so the user can see it — audio
    /// in the same batch still plays inline.
    private func playRouted(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        player.setQueue(tracks)
        if tracks.contains(where: { MediaKind.from(url: $0.url) == .video }) {
            VideoVibeWindowController.shared.show()
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 200)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    runBackfill()
                } label: {
                    if isBackfilling {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Restore Titles", systemImage: "character.bubble")
                    }
                }
                .disabled(isBackfilling || YTDLPLocator.shared.binaryURL == nil)
                .help("Re-fetch Chinese/real titles for previously downloaded YouTube files via yt-dlp (needs yt-dlp configured + network)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    runAutoClean()
                } label: {
                    if isAutoCleaning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Auto-Clean", systemImage: "wand.and.sparkles")
                    }
                }
                .disabled(isAutoCleaning || locator.downloadFolderURL == nil)
                .help("AI cleans every track: extracts real performer + song, renames file + moves to <Category>/<Performer>/ (needs download folder set)")
            }
        }
        .alert("New Playlist", isPresented: $showingNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
            Button("Create") {
                let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let p = library.createPlaylist(name: name)
                selectedPlaylistID = p.id
                newPlaylistName = ""
            }
        }
        .alert("Rename Playlist", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                if let t = renameTarget {
                    let n = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !n.isEmpty { library.renamePlaylist(id: t.id, to: n) }
                }
                renameTarget = nil
            }
        }
        .fileImporter(
            isPresented: $importerOpen,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff, .movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                _ = library.addFiles(urls)
            }
        }
        .alert(renameTrackKind == .title ? "Rename Track" : "Rename File",
               isPresented: Binding(
                    get: { renameTrackTarget != nil },
                    set: { if !$0 { renameTrackTarget = nil } }
               )) {
            TextField(renameTrackKind == .title ? "Title" : "Filename (without extension)",
                      text: $renameTrackText)
            Button("Cancel", role: .cancel) { renameTrackTarget = nil }
            Button("Save") { commitTrackRename() }
        } message: {
            if renameTrackKind == .title {
                Text("Display name for the library. File on disk is untouched.")
            } else if let t = renameTrackTarget {
                Text("Renames the file on disk. Current: \(t.url.lastPathComponent)")
            } else {
                Text("")
            }
        }
        .alert("Rename failed", isPresented: Binding(
                    get: { renameTrackError != nil },
                    set: { if !$0 { renameTrackError = nil } }
               )) {
            Button("OK", role: .cancel) { renameTrackError = nil }
        } message: {
            Text(renameTrackError ?? "")
        }
    }

    private func beginRenameTrack(_ track: Track, kind: TrackRenameKind) {
        renameTrackTarget = track
        renameTrackKind = kind
        renameTrackText = kind == .title
            ? track.title
            : track.url.deletingPathExtension().lastPathComponent
    }

    private func commitTrackRename() {
        guard let t = renameTrackTarget else { return }
        let text = renameTrackText
        let kind = renameTrackKind
        renameTrackTarget = nil
        switch kind {
        case .title:
            library.renameTrack(id: t.id, to: text)
        case .file:
            do {
                try library.renameTrackFile(id: t.id, newBaseName: text)
            } catch {
                renameTrackError = error.localizedDescription
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            libraryActionsBar
            Divider()
            sidebarList
            if isGeneratingPlaylists || !playlistGenStatus.isEmpty {
                HStack(spacing: 6) {
                    if isGeneratingPlaylists { ProgressView().controlSize(.small) }
                    Text(playlistGenStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if !isGeneratingPlaylists {
                        Button {
                            playlistGenStatus = ""
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.bar)
            }
            if isBackfilling || !backfillStatus.isEmpty {
                HStack(spacing: 6) {
                    if isBackfilling { ProgressView().controlSize(.small) }
                    Text(backfillStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if !isBackfilling {
                        Button {
                            backfillStatus = ""
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.bar)
            }
            if isAutoCleaning || !autoCleanStatus.isEmpty {
                HStack(spacing: 6) {
                    if isAutoCleaning { ProgressView().controlSize(.small) }
                    Text(autoCleanStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if !isAutoCleaning {
                        Button {
                            autoCleanStatus = ""
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.bar)
            }
            Divider()
            nowPlayingVibe
        }
    }

    private var sidebarList: some View {
        List(selection: $selectedPlaylistID) {
            Section("Library") {
                HStack {
                    Image(systemName: "music.note")
                    Text("All Tracks")
                    Spacer()
                    Text("\(library.tracks.count)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .tag(UUID?.none)
            }

            Section {
                ForEach(library.playlists) { p in
                    HStack {
                        Image(systemName: "music.note.list")
                        Text(p.name)
                        Spacer()
                        Text("\(p.trackIDs.count)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .tag(UUID?.some(p.id))
                    .contextMenu {
                        Button("Rename") {
                            renameText = p.name
                            renameTarget = p
                        }
                        Button("Play") {
                            player.setQueue(library.tracks(in: p))
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            library.deletePlaylist(id: p.id)
                            if selectedPlaylistID == p.id {
                                selectedPlaylistID = nil
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Playlists")
                    Spacer()
                    Button {
                        generatePlaylistsFromFolders()
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .buttonStyle(.borderless)
                    .help("AI: Generate playlists from the ambient folder tree")
                    .disabled(isGeneratingPlaylists || library.ambientFolderURL == nil)

                    Button {
                        newPlaylistName = ""
                        showingNewPlaylist = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Now Playing / Vibe panel

    // Pinned at the bottom of the sidebar. Two states:
    //   1. Playing → glowy mini-player card (thumbnail, title, transport).
    //   2. Idle    → "Vibes" quick picks (shuffle all audio/video, random).
    // Gradient + .ultraThinMaterial give it the Spotify-bottom-rail feel.
    private var nowPlayingVibe: some View {
        Group {
            if player.currentIndex != nil {
                nowPlayingCard
            } else {
                vibeQuickPicks
            }
        }
        .padding(10)
        .background(vibeBackground)
    }

    private var vibeBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.35),
                    Color.purple.opacity(0.18),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle().fill(.ultraThinMaterial)
        }
        .clipShape(Rectangle())
    }

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                thumbnail
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.15), lineWidth: 0.5)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Now Playing")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(nowPlayingTitle ?? "")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 14) {
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.borderless)

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)

                Button { player.next() } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button { player.shuffle.toggle() } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(player.shuffle ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)

                if currentIsVideo {
                    Button {
                        VideoVibeWindowController.shared.toggle()
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Pop out video")
                }
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if currentIsVideo {
            VideoSurface(player: player.player)
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.6), Color.purple.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "waveform")
                    .foregroundStyle(.white.opacity(0.85))
                    .font(.system(size: 22, weight: .medium))
                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
            }
        }
    }

    private var vibeQuickPicks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vibes")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            vibeButton(
                title: "Shuffle Everything",
                icon: "shuffle.circle.fill",
                countText: "\(library.tracks.count) items"
            ) {
                guard !library.tracks.isEmpty else { return }
                player.shuffle = true
                player.loop = true
                playRouted(library.tracks.shuffled())
            }
            .disabled(library.tracks.isEmpty)

            vibeButton(
                title: "Shuffle All Audio",
                icon: "shuffle",
                countText: "\(audioCount) tracks"
            ) {
                let audio = library.tracks.filter { MediaKind.from(url: $0.url) == .audio }
                guard !audio.isEmpty else { return }
                player.shuffle = true
                player.setQueue(audio.shuffled())
            }
            .disabled(audioCount == 0)

            vibeButton(
                title: "Video Vibe Mode",
                icon: "play.tv",
                countText: "\(videoCount) videos"
            ) {
                let video = library.tracks.filter { MediaKind.from(url: $0.url) == .video }
                guard !video.isEmpty else { return }
                player.shuffle = true
                player.loop = true
                player.setQueue(video.shuffled())
                VideoVibeWindowController.shared.show()
            }
            .disabled(videoCount == 0)

            vibeButton(
                title: "Surprise Me",
                icon: "sparkles",
                countText: "random pick"
            ) {
                guard let pick = library.tracks.randomElement() else { return }
                playRouted([pick])
            }
            .disabled(library.tracks.isEmpty)
        }
    }

    private func vibeButton(
        title: String,
        icon: String,
        countText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text(countText)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    // MARK: - Derived (vibe panel)

    private var audioCount: Int {
        library.tracks.filter { MediaKind.from(url: $0.url) == .audio }.count
    }

    private var videoCount: Int {
        library.tracks.filter { MediaKind.from(url: $0.url) == .video }.count
    }

    private var nowPlayingTitle: String? {
        guard let idx = player.currentIndex,
              player.queue.indices.contains(idx) else { return nil }
        return player.queue[idx].title
    }

    private var currentIsVideo: Bool {
        player.hasVideo
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let pid = selectedPlaylistID, let playlist = library.playlists.first(where: { $0.id == pid }) {
            playlistDetail(playlist)
        } else {
            allTracksDetail
        }
    }

    private var allTracksDetail: some View {
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

    // Inline action strip at the top of the sidebar — sheet-presented
    // NavigationSplitView doesn't reliably surface .toolbar items on macOS,
    // so these live in view space instead.
    private var libraryActionsBar: some View {
        HStack(spacing: 6) {
            Button {
                runBackfill()
            } label: {
                HStack(spacing: 4) {
                    if isBackfilling {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "character.bubble")
                    }
                    Text("Restore Titles")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isBackfilling || YTDLPLocator.shared.binaryURL == nil)
            .help("Re-fetch Chinese/real titles via yt-dlp")

            Button {
                runAutoClean()
            } label: {
                HStack(spacing: 4) {
                    if isAutoCleaning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "wand.and.sparkles")
                    }
                    Text("Auto-Clean")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isAutoCleaning || locator.downloadFolderURL == nil)
            .help("AI extracts performer + song, renames + moves into Category/Performer folders")

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func runAutoClean() {
        guard let root = locator.downloadFolderURL else { return }
        isAutoCleaning = true
        autoCleanStatus = "Starting…"
        Task {
            await LibraryAutoClean.run(library: library, underRoot: root) { status in
                switch status {
                case .progress(_, _, let msg):
                    autoCleanStatus = msg
                case .done(let outcome):
                    isAutoCleaning = false
                    autoCleanStatus = "Done — \(outcome.renamed) renamed, \(outcome.skipped) skipped, \(outcome.failed) failed (of \(outcome.scanned))."
                }
            }
        }
    }

    private func runBackfill() {
        guard let binary = YTDLPLocator.shared.binaryURL else { return }
        isBackfilling = true
        backfillStatus = "Starting…"
        Task {
            await YTDLPMetadataBackfill.run(library: library, binary: binary) { status in
                switch status {
                case .progress(let idx, let total, let message):
                    backfillStatus = "[\(idx)/\(total)] \(message)"
                case .done(let outcome):
                    isBackfilling = false
                    backfillStatus = "Done — \(outcome.updated) updated, \(outcome.skipped) skipped, \(outcome.failed) failed (of \(outcome.scanned) candidates)."
                }
            }
        }
    }

    private func generatePlaylistsFromFolders() {
        guard let root = library.ambientFolderURL else { return }
        isGeneratingPlaylists = true
        playlistGenStatus = "Starting…"
        Task {
            let result = await library.generatePlaylistsFromFolders(
                root: root,
                useAI: true,
                onStatus: { status in
                    playlistGenStatus = status
                }
            )
            isGeneratingPlaylists = false
            playlistGenStatus = "Created \(result.created), updated \(result.updated)."
        }
    }

    private func autoOrganize(_ tracks: [Track]) {
        guard let root = locator.downloadFolderURL else { return }
        isOrganizing = true
        organizeStatus = "Starting…"
        Task {
            var moved = 0
            var failed = 0
            for t in tracks {
                await MainActor.run {
                    organizeStatus = "Classifying \(t.title)…"
                }
                do {
                    let newURL = try await MediaCategorizer.organize(url: t.url, underRoot: root)
                    await MainActor.run {
                        library.updateTrackURL(id: t.id, newURL: newURL)
                        moved += 1
                    }
                } catch {
                    await MainActor.run {
                        failed += 1
                        organizeStatus = "\(t.title): \(error.localizedDescription)"
                    }
                }
            }
            await MainActor.run {
                isOrganizing = false
                organizeStatus = "Organized \(moved), failed \(failed)."
            }
        }
    }

    private func playlistDetail(_ playlist: Playlist) -> some View {
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

    private func detailHeader<Actions: View>(
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

    private func trackTable(_ tracks: [Track], onRemove: @escaping (UUID) -> Void) -> some View {
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
                // Single-selection rename: alert takes one value at a time, so
                // bulk rename doesn't make sense here.
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
