import SwiftUI
import AVKit
import AppKit

// Floating, always-on-top video surface bound to the shared AmbientPlayer.
// This is the "pop-out" counterpart to the tiny thumbnail shown inline on
// the ambient bar — both surfaces share the same AVPlayer so scrubbing,
// pausing, or skipping in either stays in sync.
@MainActor
final class VideoVibeWindowController: NSWindowController, NSWindowDelegate {
    static let shared = VideoVibeWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Video Vibe"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("VideoVibeWindow")

        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: VideoVibeView())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func toggle() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
    }

    var isVisible: Bool { window?.isVisible ?? false }
}

struct VideoVibeView: View {
    @StateObject private var player = AmbientPlayer.shared
    @State private var showControls: Bool = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoSurface(player: player.player)

            VStack {
                Spacer()
                if showControls {
                    controls
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .transition(.opacity)
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                showControls = hovering
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Text(currentTitle ?? "No track")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
            }
            .buttonStyle(.borderless)
            .disabled(player.queue.isEmpty)

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .disabled(player.queue.isEmpty)

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
            }
            .buttonStyle(.borderless)
            .disabled(player.queue.isEmpty)

            Divider().frame(height: 14)

            Button { player.isMuted.toggle() } label: {
                Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(player.isMuted ? .secondary : .primary)
            }
            .buttonStyle(.borderless)
            .help("Mute")
        }
        .font(.system(size: 12))
    }

    private var currentTitle: String? {
        guard let idx = player.currentIndex,
              player.queue.indices.contains(idx) else { return nil }
        return player.queue[idx].title
    }
}

// Pure-render video surface. Uses AVPlayerLayer (CALayer) instead of
// AVPlayerView so multiple surfaces can share one AVPlayer without fighting
// over transport state — AVPlayerView attaches as the player's controller
// and can pause/reset state when a second AVPlayerView binds to the same
// player (sheet open, pop-out window shown, etc). AVPlayerLayer is purely a
// rendering sink: decode once, draw into N layers, never touch play state.
struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerLayerHost {
        let v = AVPlayerLayerHost()
        v.avPlayer = player
        return v
    }

    func updateNSView(_ nsView: AVPlayerLayerHost, context: Context) {
        if nsView.avPlayer !== player {
            nsView.avPlayer = player
        }
    }
}

final class AVPlayerLayerHost: NSView {
    private let playerLayer = AVPlayerLayer()

    var avPlayer: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        playerLayer.frame = bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
