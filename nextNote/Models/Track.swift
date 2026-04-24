import Foundation

// Audio track known to the media library. The bookmark is the security-scoped
// access blob — resolving it on launch is how we regain read permission for
// files outside the vault sandbox scope (user Music folder, etc.).
struct Track: Identifiable, Equatable, Hashable {
    let id: UUID
    let url: URL
    let title: String
    let bookmark: Data?
}

// Named collection of track IDs. Ordering matters — playlists are played in
// the stored order (shuffle is a playback-time transform).
//
// `sourceFolder` is set when the playlist was auto-generated from a folder
// scan (absolute path). Used so repeat runs update in place instead of
// duplicating the playlist. nil for user-created playlists.
struct Playlist: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var trackIDs: [UUID]
    var sourceFolder: String?

    init(id: UUID, name: String, trackIDs: [UUID], sourceFolder: String? = nil) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.sourceFolder = sourceFolder
    }
}
