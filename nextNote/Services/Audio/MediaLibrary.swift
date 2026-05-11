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

    private var didBootstrap = false

    private init() {
        // Empty on purpose — bookmark resolution + fileExists per track on the
        // main thread froze the app at launch. Call bootstrap() once from the
        // first ContentView appearance instead.
    }

    /// Loads tracks/playlists/ambient folder off the main thread, then prunes
    /// any tracks whose underlying file vanished. Safe to call multiple times.
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        let restored = await Task.detached(priority: .userInitiated) {
            MediaTrackPersistence.load()
        }.value
        // Dedupe by on-disk path. Earlier builds re-ran restoreTracks on
        // hot paths and appended duplicates each time, which is why the
        // sidebar showed two identical "Jay Chou - Mojito (2)" rows.
        var seenPaths = Set<String>()
        var deduped: [Track] = []
        for t in restored.tracks {
            let key = t.url.standardizedFileURL.path
            if seenPaths.insert(key).inserted {
                deduped.append(t)
            }
        }
        tracks.append(contentsOf: deduped)
        scopedURLs.formUnion(restored.scopedURLs)
        if deduped.count != restored.tracks.count {
            // Persist the cleaned list so the bad rows don't come back next
            // launch.
            persistTracks()
        }

        restorePlaylists()
        restoreAmbientFolder()

        let snapshot = tracks
        let missing = await Task.detached(priority: .utility) {
            snapshot.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
        }.value
        if !missing.isEmpty {
            removeTracks(ids: Set(missing.map { $0.id }))
        }
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

