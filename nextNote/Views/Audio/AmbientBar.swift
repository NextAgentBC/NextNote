import SwiftUI
import UniformTypeIdentifiers

// Thin "vibe player" strip. Sits above the StatusBar, always visible. Drop
// audio files onto it → they get added to the library and enqueued. Library
// button opens the full media manager (tracks + playlists).
struct AmbientBar: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var player = AmbientPlayer.shared
    @StateObject private var library = MediaLibrary.shared
    @State private var showQueuePopover: Bool = false
    @State private var importerOpen: Bool = false
    @State private var collapsed: Bool = UserDefaults.standard.bool(forKey: "ambientBarCollapsed")
    @State private var isDropTarget: Bool = false

    var body: some View {
        Group {
            if collapsed {
                collapsedView
            } else {
                expandedView
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(isDropTarget ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .background(.bar)
        .dropDestination(for: URL.self) { urls, _ in
            let added = library.addFiles(urls)
            if !added.isEmpty { player.enqueue(added) }
            return true
        } isTargeted: { isDropTarget = $0 }
        .fileImporter(
            isPresented: $importerOpen,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                let added = library.addFiles(urls)
                if !added.isEmpty { player.enqueue(added) }
            }
        }
    }

    // MARK: - Layouts

    private var collapsedView: some View {
        HStack(spacing: 8) {
            Button {
                collapsed = false
                UserDefaults.standard.set(false, forKey: "ambientBarCollapsed")
            } label: {
                Image(systemName: "music.note")
            }
            .buttonStyle(.borderless)
            .help("Show ambient player")

            if player.isPlaying, let title = currentTitle {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var expandedView: some View {
        HStack(spacing: 10) {
            transportControls

            Divider().frame(height: 20)

            // Tiny video thumbnail — only rendered when the current item has
            // a video track. Clicking pops out the floating window. The
            // surface is bound to the shared AmbientPlayer.player, so both
            // here and the pop-out decode the same stream once.
            if player.hasVideo {
                VideoSurface(player: player.player)
                    .frame(width: 64, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.separator, lineWidth: 0.5)
                    )
                    .onTapGesture(count: 2) {
                        VideoVibeWindowController.shared.show()
                    }
                    .help("Double-click to pop out")

                Button {
                    VideoVibeWindowController.shared.toggle()
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.borderless)
                .help("Pop out video window")

                Divider().frame(height: 20)
            }

            titleAndScrub

            Divider().frame(height: 20)

            volumeSlider

            Divider().frame(height: 20)

            modeToggles

            queueAndLibrary

            Button {
                collapsed = true
                UserDefaults.standard.set(true, forKey: "ambientBarCollapsed")
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Hide ambient player")
        }
        .font(.system(size: 12))
    }

    // MARK: - Components

    private var transportControls: some View {
        HStack(spacing: 4) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(.borderless)
            .disabled(player.queue.isEmpty)

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .frame(width: 20)
            }
            .buttonStyle(.borderless)
            .disabled(player.queue.isEmpty)

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(.borderless)
            .disabled(player.queue.isEmpty)
        }
    }

    private var titleAndScrub: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(currentTitle ?? "Drop audio here, or open Library")
                    .lineLimit(1)
                    .foregroundStyle(currentTitle == nil ? .secondary : .primary)
                Spacer()
                if player.duration > 0 {
                    Text("\(fmt(player.currentTime)) / \(fmt(player.duration))")
                        .foregroundStyle(.secondary)
                        .font(.caption.monospacedDigit())
                }
            }
            Slider(
                value: Binding(
                    get: {
                        player.duration > 0 ? player.currentTime / player.duration : 0
                    },
                    set: { player.seek(toFraction: $0) }
                )
            )
            .controlSize(.mini)
            .disabled(player.duration == 0)
        }
        .frame(maxWidth: 320)
    }

    private var volumeSlider: some View {
        HStack(spacing: 4) {
            Image(systemName: volumeIcon)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Slider(
                value: Binding(
                    get: { Double(player.volume) },
                    set: { player.volume = Float($0) }
                ),
                in: 0...1
            )
            .controlSize(.mini)
            .frame(width: 70)
        }
    }

    private var modeToggles: some View {
        HStack(spacing: 6) {
            Button {
                player.shuffle.toggle()
            } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(player.shuffle ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Shuffle")

            Button {
                player.loop.toggle()
            } label: {
                Image(systemName: "repeat")
                    .foregroundStyle(player.loop ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help("Loop queue")
        }
    }

    private var queueAndLibrary: some View {
        HStack(spacing: 4) {
            Button {
                importerOpen = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add audio files")

            Button {
                shuffleEntireLibrary()
            } label: {
                Image(systemName: "shuffle.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(library.tracks.isEmpty)
            .help("Shuffle entire media library (\(library.tracks.count) items)")

            Button {
                showQueuePopover.toggle()
            } label: {
                Image(systemName: "list.bullet")
                Text("\(player.queue.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Now-playing queue")
            .popover(isPresented: $showQueuePopover, arrowEdge: .top) {
                queuePopover
            }

            Button {
                appState.showYouTubeDownload = true
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .help("Download from YouTube")

            Button {
                VideoVibeWindowController.shared.toggle()
            } label: {
                Image(systemName: "play.tv")
            }
            .buttonStyle(.borderless)
            .help("Toggle Video Vibe window")
        }
    }

    private var queuePopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Queue").font(.headline)
                Spacer()
                if !player.queue.isEmpty {
                    Button("Clear", role: .destructive) {
                        player.clear()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            if player.queue.isEmpty {
                Text("Nothing queued. Drop files on the bar or load a playlist.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(player.queue.enumerated()), id: \.element.id) { idx, track in
                            HStack {
                                Image(systemName: idx == player.currentIndex
                                      ? (player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                      : "music.note")
                                    .frame(width: 16)
                                    .foregroundStyle(idx == player.currentIndex ? Color.accentColor : .secondary)
                                Text(track.title)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    player.remove(at: idx)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(idx == player.currentIndex ? Color.accentColor.opacity(0.1) : Color.clear)
                            .onTapGesture {
                                player.play(at: idx)
                            }
                        }
                    }
                }
                .frame(width: 320, height: 280)
            }
        }
        .frame(minWidth: 320)
    }

    // MARK: - Derived

    private var currentTitle: String? {
        guard let idx = player.currentIndex,
              player.queue.indices.contains(idx) else { return nil }
        return player.queue[idx].title
    }

    private var volumeIcon: String {
        switch player.volume {
        case 0: return "speaker.slash"
        case 0..<0.33: return "speaker.wave.1"
        case 0.33..<0.66: return "speaker.wave.2"
        default: return "speaker.wave.3"
        }
    }

    private func shuffleEntireLibrary() {
        guard !library.tracks.isEmpty else { return }
        player.shuffle = true
        player.loop = true
        let shuffled = library.tracks.shuffled()
        player.setQueue(shuffled)
        if shuffled.contains(where: { MediaKind.from(url: $0.url) == .video }) {
            VideoVibeWindowController.shared.show()
        }
    }

    private func fmt(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "--:--" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
