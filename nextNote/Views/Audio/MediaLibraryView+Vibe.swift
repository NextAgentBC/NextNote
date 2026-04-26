import SwiftUI

extension MediaLibraryView {
    /// Pinned at the bottom of the sidebar. Two states:
    ///   1. Playing → glowy mini-player card (thumbnail, title, transport).
    ///   2. Idle    → "Vibes" quick picks (shuffle all audio/video, random).
    /// Gradient + .ultraThinMaterial give it the Spotify-bottom-rail feel.
    var nowPlayingVibe: some View {
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

    var vibeBackground: some View {
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

    var nowPlayingCard: some View {
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
    var thumbnail: some View {
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

    var vibeQuickPicks: some View {
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

    func vibeButton(
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

    var audioCount: Int {
        library.tracks.filter { MediaKind.from(url: $0.url) == .audio }.count
    }

    var videoCount: Int {
        library.tracks.filter { MediaKind.from(url: $0.url) == .video }.count
    }

    var nowPlayingTitle: String? {
        guard let idx = player.currentIndex,
              player.queue.indices.contains(idx) else { return nil }
        return player.queue[idx].title
    }

    var currentIsVideo: Bool {
        player.hasVideo
    }
}
