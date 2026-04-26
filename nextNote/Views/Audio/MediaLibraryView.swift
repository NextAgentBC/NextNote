import SwiftUI
import UniformTypeIdentifiers

/// Full media manager: browse all known tracks, build named playlists,
/// queue them into the ambient player. Opened as a sheet from AmbientBar
/// or via Cmd+Shift+M. Per-area UI lives in adjacent extension files
/// (Sidebar / Vibe / Detail / Actions).
struct MediaLibraryView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var libraryRoots: LibraryRoots
    @StateObject var library = MediaLibrary.shared
    @StateObject var player = AmbientPlayer.shared
    @StateObject var locator = YTDLPLocator.shared

    @State var isOrganizing: Bool = false
    @State var organizeStatus: String = ""
    @State var isGeneratingPlaylists: Bool = false
    @State var playlistGenStatus: String = ""

    // Sidebar selection: either "All Tracks" (nil) or a specific playlist ID.
    @State var selectedPlaylistID: UUID? = nil
    @State var selectedTrackIDs: Set<UUID> = []
    @State var newPlaylistName: String = ""
    @State var showingNewPlaylist: Bool = false
    @State var renameTarget: Playlist? = nil
    @State var renameText: String = ""
    @State var importerOpen: Bool = false
    @State var kindFilter: KindFilter = .all
    @State var isBackfilling: Bool = false
    @State var backfillStatus: String = ""
    @State var isAutoCleaning: Bool = false
    @State var autoCleanStatus: String = ""
    // Track rename flow — nil when hidden. `renameTrackKind` distinguishes
    // "title only" from "file on disk" so we can reuse one alert for both.
    @State var renameTrackTarget: Track?
    @State var renameTrackText: String = ""
    @State var renameTrackKind: TrackRenameKind = .title
    @State var renameTrackError: String?

    enum TrackRenameKind { case title, file }

    enum KindFilter: String, CaseIterable {
        case all = "All"
        case audio = "Audio"
        case video = "Video"
    }

    func filter(_ tracks: [Track]) -> [Track] {
        switch kindFilter {
        case .all: return tracks
        case .audio: return tracks.filter { MediaKind.from(url: $0.url) == .audio }
        case .video: return tracks.filter { MediaKind.from(url: $0.url) == .video }
        }
    }

    /// Hand tracks off to the unified player. If the batch contains any
    /// video, also open the pop-out window so the user can see it — audio
    /// in the same batch still plays inline.
    func playRouted(_ tracks: [Track]) {
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

    func beginRenameTrack(_ track: Track, kind: TrackRenameKind) {
        renameTrackTarget = track
        renameTrackKind = kind
        renameTrackText = kind == .title
            ? track.title
            : track.url.deletingPathExtension().lastPathComponent
    }

    func commitTrackRename() {
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
}
