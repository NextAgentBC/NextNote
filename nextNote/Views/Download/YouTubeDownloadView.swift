import SwiftUI
import AppKit

/// Sheet for pulling a YouTube URL via yt-dlp. On audio success, auto-adds
/// to the media library + enqueues. On video success, just reveals in
/// Finder. First launch: user picks yt-dlp binary + a default download
/// folder (both stored as security-scoped bookmarks). Setup rows, search
/// results, and download flow live in adjacent extension files.
struct YouTubeDownloadView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var libraryRoots: LibraryRoots
    @StateObject var locator = YTDLPLocator.shared
    @StateObject var library = MediaLibrary.shared
    @StateObject var player = AmbientPlayer.shared

    @State var urlText: String = ""
    @State var mode: YTDLPDownloader.Mode = .audio
    @AppStorage("ytdlp.videoQuality") var qualityRaw: String = YTDLPDownloader.Quality.best.rawValue
    @State var searchResults: [YTDLPSearch.Result] = []
    @State var isSearching: Bool = false
    @State var searchError: String?
    @State var isRunning: Bool = false
    @State var progress: Double = 0
    @State var statusLine: String = ""
    @State var lastError: String?
    @State var lastOutputURL: URL?
    @State var currentHandle: YTDLPHandle?
    @AppStorage("ytdlp.autoClassify") var autoClassify: Bool = true
    @AppStorage("ytdlp.saveTo") var saveToRaw: String = SaveDestination.media.rawValue

    enum SaveDestination: String, CaseIterable, Identifiable {
        case media   = "Media"
        case assets  = "Assets"
        var id: String { rawValue }
    }
    var saveTo: SaveDestination {
        SaveDestination(rawValue: saveToRaw) ?? .media
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YouTube Download").font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            disclaimerBox

            // yt-dlp row — auto-adopted when present at a Homebrew path;
            // shows an install hint otherwise.
            if let bin = locator.binaryURL {
                toolStatusRow(label: "yt-dlp", path: bin.path, installed: true) {
                    Task { await locator.pickBinary() }
                }
            } else {
                installHintRow(
                    label: "yt-dlp",
                    command: "brew install yt-dlp",
                    why: "required — downloads audio/video from YouTube"
                ) {
                    Task { await locator.pickBinary() }
                }
            }

            if let pickErr = locator.lastPickError {
                Text(pickErr)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // ffmpeg row — optional but unlocks 1080p+ merged downloads.
            if let ff = locator.ffmpegURL {
                toolStatusRow(label: "ffmpeg", path: ff.path, installed: true) {
                    Task { await locator.pickFFmpeg() }
                }
            } else {
                installHintRow(
                    label: "ffmpeg",
                    command: "brew install ffmpeg",
                    why: "optional — required for resolutions above 720p and post-download HEVC transcoding"
                ) {
                    Task { await locator.pickFFmpeg() }
                }
            }

            setupRow(
                label: "Download folder",
                pathText: locator.downloadFolderURL?.path ?? "— not set —",
                action: "Choose…"
            ) {
                Task { await locator.pickDownloadFolder() }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Paste URL — or type keywords to search YouTube", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isRunning)
                    .onSubmit {
                        if YTDLPSearch.isLikelyURL(urlText) {
                            startDownload()
                        } else {
                            runSearch()
                        }
                    }
                Button {
                    runSearch()
                } label: {
                    if isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .disabled(isSearching || isRunning
                          || urlText.trimmingCharacters(in: .whitespaces).isEmpty
                          || locator.binaryURL == nil)
                .help("Search YouTube via yt-dlp")
            }

            if let err = searchError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            if !searchResults.isEmpty {
                searchResultsList
            }

            if isChannelOrPlaylistURL(urlText) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle").foregroundStyle(.blue)
                    Text("This looks like a channel or playlist page. Only the first video will be downloaded. Paste a single-video URL (youtu.be/... or watch?v=...) to target a specific track.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Format", selection: $mode) {
                Text(locator.ffmpegURL == nil ? "Audio (m4a — no ffmpeg)" : "Audio (mp3, V0 VBR)")
                    .tag(YTDLPDownloader.Mode.audio)
                Text(locator.ffmpegURL == nil ? "Video (mp4, ≤720p)" : "Video (mp4)")
                    .tag(YTDLPDownloader.Mode.video)
            }
            .pickerStyle(.segmented)
            .disabled(isRunning)

            if mode == .video {
                HStack(spacing: 8) {
                    Text("Quality")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { YTDLPDownloader.Quality(rawValue: qualityRaw) ?? .best },
                        set: { qualityRaw = $0.rawValue }
                    )) {
                        ForEach(YTDLPDownloader.Quality.allCases) { q in
                            Text(q.rawValue).tag(q)
                        }
                    }
                    .labelsHidden()
                    .disabled(isRunning)
                    if locator.ffmpegURL == nil {
                        Text("(ffmpeg off → effectively ≤720p)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Save to")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                Picker("", selection: Binding(
                    get: { saveTo },
                    set: { saveToRaw = $0.rawValue }
                )) {
                    ForEach(SaveDestination.allCases) { d in
                        Text(d.rawValue).tag(d)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(isRunning)
            }

            // AI classify only makes sense in the Media root (artist folders).
            // Assets is a flat scratch pool — skip the artist subfolder step.
            Toggle("Auto-classify into Category/Subcategory folder (uses AI)", isOn: $autoClassify)
                .disabled(isRunning || saveTo == .assets)
                .font(.caption)

            if isRunning {
                ProgressView(value: progress)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let err = lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(4)
            } else if let out = lastOutputURL {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(out.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Reveal") {
                        FinderActions.reveal(out)
                    }
                }
                .font(.caption)
            }

            HStack {
                Spacer()
                if isRunning {
                    Button("Cancel", role: .destructive) {
                        currentHandle?.cancel()
                    }
                }
                Button(isRunning ? "Downloading…" : "Download") {
                    startDownload()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canDownload)
            }
        }
        .padding(18)
        .frame(minWidth: 520)
    }
}
