import Foundation

/// Single source of truth for "play this batch of tracks" behavior. Every
/// surface (sidebar, AmbientBar, MediaLibrary, queue popover) routes through
/// here so the side effects — pop the video window, swap queue vs enqueue —
/// stay in sync.
@MainActor
enum MediaPlayback {

    /// Replace the queue with `tracks` and start. Pops the video window
    /// when any item is video.
    static func play(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        AmbientPlayer.shared.setQueue(tracks)
        if tracks.contains(where: { MediaKind.from(url: $0.url) == .video }) {
            VideoVibeWindowController.shared.show()
        }
    }

    /// Append `tracks` to the existing queue. Pops the video window when
    /// any item is video so the user notices it landed in the queue.
    static func enqueue(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        AmbientPlayer.shared.enqueue(tracks)
        if tracks.contains(where: { MediaKind.from(url: $0.url) == .video }) {
            VideoVibeWindowController.shared.show()
        }
    }

    /// Toggle play/pause. If the queue is empty but the library has tracks,
    /// load the whole library and play (with video-window auto-pop).
    static func togglePlayPause() {
        let player = AmbientPlayer.shared
        if player.queue.isEmpty {
            let lib = MediaLibrary.shared.tracks
            if !lib.isEmpty { play(lib) }
            return
        }
        player.togglePlayPause()
    }

    /// Shuffle the entire library.
    static func shuffleLibrary() {
        var t = MediaLibrary.shared.tracks
        guard !t.isEmpty else { return }
        t.shuffle()
        AmbientPlayer.shared.shuffle = true
        AmbientPlayer.shared.loop = true
        play(t)
    }
}
