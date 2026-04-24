import SwiftUI
import AVKit
import UniformTypeIdentifiers

/// Standalone media tab content. Uses the AppKit-native `AVPlayerView` —
/// SwiftUI's `VideoPlayer` crashes in `_AVKit_SwiftUI` generic metadata init
/// on macOS 26 betas, so we route through the NSViewRepresentable bridge.
///
/// For video kind, overlays a toolbar exposing trim (via AVPlayerView's
/// built-in trimming UI) and a queue+concat export workflow.
struct MediaPlayerView: View {
    let url: URL
    let kind: MediaKind

    @StateObject private var session = VideoSession()

    var body: some View {
        VStack(spacing: 0) {
            if kind == .video {
                videoToolbar
                    .padding(8)
                    .background(.bar)
                Divider()
            }

            ZStack {
                Color(NSColor.textBackgroundColor)
                AVPlayerViewRepresentable(url: url, session: session)

                if kind == .audio {
                    VStack {
                        Spacer()
                        Image(systemName: "waveform")
                            .font(.system(size: 72))
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                        Spacer()
                        Spacer()
                    }
                }
            }

            if kind == .video && !session.concatQueue.isEmpty {
                Divider()
                concatQueueList
                    .frame(maxHeight: 140)
            }
        }
        .alert("Export error", isPresented: .init(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button("OK") { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
        .overlay {
            if session.isExporting {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView(value: session.exportProgress)
                            .frame(width: 260)
                        Text("Exporting… \(Int(session.exportProgress * 100))%")
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    // MARK: - Video toolbar

    @ViewBuilder
    private var videoToolbar: some View {
        HStack(spacing: 8) {
            Button {
                trimCurrent()
            } label: {
                Label("Trim…", systemImage: "scissors")
            }
            .help("Open trim editor; save clipped copy to a new file.")

            Button {
                stripAudioCurrent()
            } label: {
                Label("Remove Audio…", systemImage: "speaker.slash")
            }
            .help("Export a video-only copy with the audio track removed.")

            Button {
                if !session.concatQueue.contains(url) {
                    session.concatQueue.append(url)
                }
            } label: {
                Label("Add to Concat Queue", systemImage: "plus.rectangle.on.rectangle")
            }

            Spacer()

            if !session.concatQueue.isEmpty {
                Text("Queue: \(session.concatQueue.count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Button {
                    session.concatQueue.removeAll()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }

                Button {
                    exportConcat()
                } label: {
                    Label("Export Concat", systemImage: "square.stack.3d.down.right")
                }
                .keyboardShortcut("e", modifiers: [.command])
                .disabled(session.concatQueue.count < 2)
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.bordered)
        .disabled(session.isExporting)
    }

    @ViewBuilder
    private var concatQueueList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Concat Queue").font(.caption.bold())
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            List {
                ForEach(Array(session.concatQueue.enumerated()), id: \.offset) { idx, fileURL in
                    HStack {
                        Text("\(idx + 1).")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(fileURL.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            session.concatQueue.remove(at: idx)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onMove { from, to in
                    session.concatQueue.move(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Actions

    @MainActor
    private func trimCurrent() {
        guard let playerView = session.playerView else { return }
        guard playerView.canBeginTrimming else {
            session.lastError = "This asset cannot be trimmed."
            return
        }
        let sourceName = url.deletingPathExtension().lastPathComponent
        playerView.beginTrimming { result in
            Task { @MainActor in
                guard result == .okButton,
                      let item = playerView.player?.currentItem else { return }
                let start = item.reversePlaybackEndTime
                let end = item.forwardPlaybackEndTime
                let sStart = CMTIME_IS_VALID(start) && !CMTIME_IS_INDEFINITE(start) ? start : .zero
                let sEnd = CMTIME_IS_VALID(end) && !CMTIME_IS_INDEFINITE(end) ? end : item.duration
                let range = CMTimeRange(start: sStart, end: sEnd)

                guard let dest = await promptSavePanel(
                    suggested: sourceName + "-trim.mp4"
                ) else { return }
                let capturedSession = session
                let sourceURL = url
                await runExport {
                    try await VideoExporter.trim(
                        asset: AVURLAsset(url: sourceURL),
                        timeRange: range,
                        to: dest,
                        progress: { p in
                            Task { @MainActor in capturedSession.exportProgress = p }
                        }
                    )
                }
            }
        }
    }

    @MainActor
    private func stripAudioCurrent() {
        let sourceName = url.deletingPathExtension().lastPathComponent
        let sourceURL = url
        let capturedSession = session
        Task { @MainActor in
            guard let dest = await promptSavePanel(
                suggested: sourceName + "-muted.mp4"
            ) else { return }
            await runExport {
                try await VideoExporter.stripAudio(
                    asset: AVURLAsset(url: sourceURL),
                    to: dest,
                    progress: { p in
                        Task { @MainActor in capturedSession.exportProgress = p }
                    }
                )
            }
        }
    }

    @MainActor
    private func exportConcat() {
        let urls = session.concatQueue
        let capturedSession = session
        Task { @MainActor in
            guard let dest = await promptSavePanel(suggested: "concat.mp4") else { return }
            await runExport {
                try await VideoExporter.concat(
                    urls: urls,
                    to: dest,
                    progress: { p in
                        Task { @MainActor in capturedSession.exportProgress = p }
                    }
                )
            }
        }
    }

    @MainActor
    private func runExport(_ op: @Sendable @escaping () async throws -> Void) async {
        session.isExporting = true
        session.exportProgress = 0
        defer { session.isExporting = false }
        do {
            try await op()
        } catch {
            session.lastError = error.localizedDescription
        }
    }

    @MainActor
    private func promptSavePanel(suggested: String) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.allowedContentTypes = [UTType.mpeg4Movie]
        panel.canCreateDirectories = true
        let resp = await panel.beginSheet()
        guard resp == .OK, let out = panel.url else { return nil }
        return out
    }
}

// MARK: - Session

@MainActor
final class VideoSession: ObservableObject {
    @Published var concatQueue: [URL] = []
    @Published var isExporting: Bool = false
    @Published var exportProgress: Double = 0
    @Published var lastError: String?

    // Weak ref so dismantle doesn't leak; AVPlayerView lives in NSViewRepresentable.
    weak var playerView: AVPlayerView?
}

// MARK: - AVPlayerView bridge

private struct AVPlayerViewRepresentable: NSViewRepresentable {
    let url: URL
    let session: VideoSession

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.player = AVPlayer(url: url)
        view.player?.preventsDisplaySleepDuringVideoPlayback = true
        Task { @MainActor in session.playerView = view }
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        // Swap players only when the URL actually changes; SwiftUI may
        // re-invoke updateNSView for unrelated reasons and we don't want to
        // reset playback state every render.
        let currentURL = (view.player?.currentItem?.asset as? AVURLAsset)?.url
        guard currentURL != url else { return }
        view.player?.pause()
        view.player = AVPlayer(url: url)
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

// MARK: - NSSavePanel async helper

private extension NSSavePanel {
    @MainActor
    func beginSheet() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { cont in
            if let window = NSApp.keyWindow {
                self.beginSheetModal(for: window) { resp in
                    cont.resume(returning: resp)
                }
            } else {
                let resp = self.runModal()
                cont.resume(returning: resp)
            }
        }
    }
}
