import Foundation
import AVFoundation
import Combine

// Unified audio + video player. One AVPlayer instance drives everything —
// the ambient bar shows a small video thumbnail when the current track
// carries a video stream, and the floating "vibe" window binds to the same
// player so both surfaces stay in sync without duplicate decoding.
@MainActor
final class AmbientPlayer: ObservableObject {
    static let shared = AmbientPlayer()

    @Published private(set) var queue: [Track] = []
    @Published private(set) var currentIndex: Int? = nil
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var hasVideo: Bool = false
    @Published var volume: Float = 0.6 {
        didSet { player.volume = volume; persistControls() }
    }
    @Published var shuffle: Bool = false { didSet { persistControls() } }
    @Published var loop: Bool = true { didSet { persistControls() } }
    @Published var isMuted: Bool = false {
        didSet { player.isMuted = isMuted; persistControls() }
    }

    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    // One player for the lifetime of the app. AVPlayerView surfaces (tiny
    // thumbnail + floating window) latch onto this; replaceCurrentItem()
    // drives track changes without tearing down the players.
    let player = AVPlayer()

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    private static let volumeKey = "ambientVolume"
    private static let shuffleKey = "ambientShuffle"
    private static let loopKey = "ambientLoop"
    private static let mutedKey = "ambientMuted"

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: Self.volumeKey) != nil {
            volume = d.float(forKey: Self.volumeKey)
        }
        shuffle = d.bool(forKey: Self.shuffleKey)
        loop = d.object(forKey: Self.loopKey) == nil ? true : d.bool(forKey: Self.loopKey)
        isMuted = d.bool(forKey: Self.mutedKey)
        player.volume = volume
        player.isMuted = isMuted
        installPeriodicObserver()
    }

    // MARK: - Queue

    /// Convenience: build a one-off Track from a URL and start it. Used by
    /// the sidebar "click a file, it plays" flow. The Track is transient —
    /// not persisted to MediaLibrary.
    func playURL(_ url: URL, title: String? = nil) {
        let name = title ?? url.deletingPathExtension().lastPathComponent
        let track = Track(id: UUID(), url: url, title: name, bookmark: nil)
        setQueue([track])
    }

    func setQueue(_ tracks: [Track], startAt index: Int = 0) {
        stop()
        queue = tracks
        guard !tracks.isEmpty else {
            currentIndex = nil
            return
        }
        play(at: min(max(index, 0), tracks.count - 1))
    }

    func enqueue(_ tracks: [Track]) {
        let wasEmpty = queue.isEmpty
        queue.append(contentsOf: tracks)
        if wasEmpty, let first = queue.indices.first {
            play(at: first)
        }
    }

    func remove(at index: Int) {
        guard queue.indices.contains(index) else { return }
        if currentIndex == index {
            stop()
        }
        queue.remove(at: index)
        if let cur = currentIndex {
            if cur > index { currentIndex = cur - 1 }
            else if cur == index { currentIndex = nil }
        }
    }

    func clear() {
        stop()
        queue.removeAll()
        currentIndex = nil
    }

    /// Purge any queued tracks matching these IDs. If the currently-playing
    /// track is among them, stop playback. Called by MediaLibrary when a
    /// track is removed — keeps the player from continuing a phantom stream.
    func removeTracks(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty, !queue.isEmpty else { return }
        let currentID = currentIndex.flatMap { queue.indices.contains($0) ? queue[$0].id : nil }
        let currentDoomed = currentID.map { ids.contains($0) } ?? false
        if currentDoomed {
            stop()
        }
        queue.removeAll { ids.contains($0.id) }
        if currentDoomed {
            currentIndex = nil
        } else if let cid = currentID,
                  let newIdx = queue.firstIndex(where: { $0.id == cid }) {
            currentIndex = newIdx
        } else {
            currentIndex = nil
        }
    }

    // MARK: - Playback

    func play(at index: Int) {
        guard queue.indices.contains(index) else { return }
        let track = queue[index]
        let item = AVPlayerItem(url: track.url)
        teardownItemObservers()
        player.replaceCurrentItem(with: item)
        currentIndex = index
        isPlaying = true
        duration = 0
        currentTime = 0
        hasVideo = false
        attachItemObservers(for: item)
        player.play()

        // Kind-by-extension is a fast hint; actual video-track detection
        // confirms once the asset loads. Both feed `hasVideo` so UI reacts
        // immediately when opening an mp4, then corrects itself for edge
        // cases like audio-only .mov containers.
        let extHint = MediaKind.from(url: track.url) == .video
        if extHint { hasVideo = true }
        Task { await self.refreshHasVideo(for: item) }
    }

    func togglePlayPause() {
        if player.currentItem == nil {
            if let first = queue.indices.first { play(at: first) }
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func next() {
        guard !queue.isEmpty else { return }
        if shuffle {
            let others = queue.indices.filter { $0 != currentIndex }
            guard let pick = others.randomElement() else { return }
            play(at: pick)
            return
        }
        let cur = currentIndex ?? -1
        let nextIdx = cur + 1
        if nextIdx >= queue.count {
            if loop { play(at: 0) } else { stop() }
        } else {
            play(at: nextIdx)
        }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 3 {
            player.seek(to: .zero)
            return
        }
        let cur = currentIndex ?? 0
        let prev = cur - 1
        if prev < 0 {
            if loop { play(at: queue.count - 1) }
        } else {
            play(at: prev)
        }
    }

    func seek(toFraction fraction: Double) {
        guard duration > 0 else { return }
        let target = CMTime(seconds: duration * fraction, preferredTimescale: 600)
        player.seek(to: target)
    }

    func stop() {
        teardownItemObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        hasVideo = false
        currentTime = 0
        duration = 0
    }

    // MARK: - Observers

    private func installPeriodicObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] t in
            guard let self else { return }
            self.currentTime = t.seconds
            if let d = self.player.currentItem?.duration.seconds, d.isFinite {
                self.duration = d
            }
        }
    }

    private func attachItemObservers(for item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.next() }
        }
    }

    private func teardownItemObservers() {
        if let end = endObserver {
            NotificationCenter.default.removeObserver(end)
        }
        endObserver = nil
    }

    private func refreshHasVideo(for item: AVPlayerItem) async {
        do {
            let tracks = try await item.asset.loadTracks(withMediaType: .video)
            let detected = !tracks.isEmpty
            await MainActor.run {
                // Only update if this is still the active item — a fast
                // next() before the asset load completes shouldn't stomp the
                // next track's state.
                if self.player.currentItem === item {
                    self.hasVideo = detected
                }
            }
        } catch {
            // Leave the extension-based hint in place on asset load failure.
        }
    }

    // MARK: - Persistence

    private func persistControls() {
        let d = UserDefaults.standard
        d.set(volume, forKey: Self.volumeKey)
        d.set(shuffle, forKey: Self.shuffleKey)
        d.set(loop, forKey: Self.loopKey)
        d.set(isMuted, forKey: Self.mutedKey)
    }
}
