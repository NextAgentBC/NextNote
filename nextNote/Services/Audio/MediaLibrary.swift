import Foundation
import Combine
import AppKit

/// App-wide audio library. Owns the master list of tracks (each with a
/// security-scoped bookmark so access survives relaunch) and the set of
/// user-created playlists.
///
/// Playback is driven by AmbientPlayer, which the library pushes queues
/// into on demand — the library itself doesn't play anything.
///
/// Track CRUD / playlist CRUD / ambient-folder picking / scanning live in
/// adjacent extension files (+Tracks, +Playlists, +AmbientFolder, +Scan).
@MainActor
final class MediaLibrary: ObservableObject {
    static let shared = MediaLibrary()

    @Published var tracks: [Track] = []
    @Published var playlists: [Playlist] = []
    @Published var ambientFolderURL: URL?
    @Published var isScanning: Bool = false

    /// A single collapsible group in the sidebar — one per parent folder
    /// under the scan root.
    struct MediaGroup: Identifiable, Hashable {
        var id: String { "\(kind.rawValue)/\(folder)" }
        var folder: String
        var kind: MediaKind
        var items: [Track]
    }

    var scopedURLs: Set<URL> = []
    var ambientFolderScope: URL?

    /// True once the user has answered the first-launch prompt (either
    /// picking a folder or declining). Used to suppress the prompt on
    /// subsequent launches.
    var hasPromptedForAmbientFolder: Bool {
        AmbientFolderBookmark.hasPrompted
    }

    /// True when the prompt should be shown this launch: we haven't asked
    /// before, and no folder has been set.
    var shouldPromptForAmbientFolder: Bool {
        !hasPromptedForAmbientFolder && ambientFolderURL == nil
    }

    func markPrompted() {
        AmbientFolderBookmark.markPrompted()
    }

    private init() {
        restoreTracks()
        restorePlaylists()
        restoreAmbientFolder()
        // Drop tracks whose file vanished since last launch (deleted in
        // Finder, external drive gone, vault cleared, etc). Keeps the
        // library from resurrecting ghost entries through stale bookmarks.
        _ = pruneMissing()
    }

    deinit {
        for url in scopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        ambientFolderScope?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Persistence wrappers (helpers live in *Persistence files)

    func persistTracks() {
        MediaTrackPersistence.save(tracks)
    }

    func persistPlaylists() {
        PlaylistPersistence.save(playlists)
    }

    func restoreTracks() {
        let restored = MediaTrackPersistence.load()
        tracks.append(contentsOf: restored.tracks)
        scopedURLs.formUnion(restored.scopedURLs)
    }

    func restorePlaylists() {
        playlists.append(contentsOf: PlaylistPersistence.load())
    }
}

