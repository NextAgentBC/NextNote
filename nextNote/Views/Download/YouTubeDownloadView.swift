import SwiftUI
import AppKit

// Sheet for pulling a YouTube URL via yt-dlp. On audio success, auto-adds to
// the media library + enqueues. On video success, just reveals in Finder.
//
// First launch: user picks yt-dlp binary (brew install yt-dlp) and a default
// download folder. Both are persisted as security-scoped bookmarks.
struct YouTubeDownloadView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var libraryRoots: LibraryRoots
    @StateObject private var locator = YTDLPLocator.shared
    @StateObject private var library = MediaLibrary.shared
    @StateObject private var player = AmbientPlayer.shared

    @State private var urlText: String = ""
    @State private var mode: YTDLPDownloader.Mode = .audio
    @AppStorage("ytdlp.videoQuality") private var qualityRaw: String = YTDLPDownloader.Quality.best.rawValue
    @State private var searchResults: [YTDLPSearch.Result] = []
    @State private var isSearching: Bool = false
    @State private var searchError: String?
    @State private var isRunning: Bool = false
    @State private var progress: Double = 0
    @State private var statusLine: String = ""
    @State private var lastError: String?
    @State private var lastOutputURL: URL?
    @State private var currentHandle: YTDLPHandle?
    @AppStorage("ytdlp.autoClassify") private var autoClassify: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YouTube Download").font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            disclaimerBox

            setupRow(
                label: "yt-dlp binary",
                pathText: locator.binaryURL?.path ?? "— not set —",
                action: "Choose…"
            ) {
                Task { await locator.pickBinary() }
            }

            if locator.binaryURL == nil, let detected = YTDLPLocator.detectedBinaryPath {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(.blue)
                    Text("Detected yt-dlp at \(detected). Click \"Choose…\" — the file picker will land on it; just press Open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if locator.binaryURL == nil {
                HStack(spacing: 6) {
                    Image(systemName: "terminal").foregroundStyle(.secondary)
                    Text("Install first: `brew install yt-dlp`, then click Choose…")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            if let pickErr = locator.lastPickError {
                Text(pickErr)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            setupRow(
                label: "ffmpeg (optional)",
                pathText: locator.ffmpegURL?.path ?? (YTDLPLocator.detectedFFmpegPath.map { "— detected at \($0), click Choose" } ?? "— not set, max 720p without it"),
                action: "Choose…"
            ) {
                Task { await locator.pickFFmpeg() }
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

            Toggle("Auto-classify into Category/Subcategory folder (uses AI)", isOn: $autoClassify)
                .disabled(isRunning)
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
                        NSWorkspace.shared.activateFileViewerSelecting([out])
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

    // MARK: - Subviews

    private var disclaimerBox: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("YouTube's Terms of Service restrict downloading. Use only for content you own or have explicit rights to — you are responsible for compliance.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private func setupRow(
        label: String,
        pathText: String,
        action: String,
        onAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(pathText)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
            Spacer()
            Button(action, action: onAction)
                .controlSize(.small)
                .disabled(isRunning)
        }
    }

    // MARK: - Actions

    private var canDownload: Bool {
        !isRunning
            && locator.binaryURL != nil
            && locator.downloadFolderURL != nil
            && !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func startDownload() {
        guard let binary = locator.binaryURL,
              let folder = locator.downloadFolderURL else { return }
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenMode = mode
        let handle = YTDLPHandle()
        currentHandle = handle

        isRunning = true
        progress = 0
        statusLine = "Starting…"
        lastError = nil
        lastOutputURL = nil

        Task {
            do {
                let quality = YTDLPDownloader.Quality(rawValue: qualityRaw) ?? .best
                let result = try await YTDLPDownloader.download(
                    videoURL: url,
                    mode: chosenMode,
                    quality: quality,
                    folder: folder,
                    binary: binary,
                    ffmpeg: locator.ffmpegURL,
                    handle: handle,
                    progress: { p, line in
                        Task { @MainActor in
                            if p >= 0 { progress = p }
                            statusLine = line
                        }
                    }
                )
                // Classify + move BEFORE registering in library — keeps the
                // bookmark aimed at the final path from the start.
                //
                // Prefer the Media library root over the yt-dlp download
                // folder so the classifier creates <mediaRoot>/<Artist>/...
                // subdirectories. Otherwise auto-classified files land in
                // sibling folders next to mediaRoot (e.g. ~/yt/Unknown/)
                // and never appear in the left sidebar, which only scans
                // under mediaRoot.
                var finalURL = result.outputURL
                if autoClassify {
                    await MainActor.run { statusLine = "Classifying with AI…" }
                    let m = result.metadata
                    let ctx = MediaCategorizer.Context(
                        uploader: m.uploader,
                        channel: m.channel,
                        categories: m.categories,
                        tags: m.tags,
                        playlist: m.playlist
                    )
                    let classifyRoot = await MainActor.run { libraryRoots.mediaRoot } ?? folder
                    do {
                        finalURL = try await MediaCategorizer.organize(
                            url: result.outputURL,
                            underRoot: classifyRoot,
                            preferredTitle: m.title,
                            context: ctx.isEmpty ? nil : ctx
                        )
                    } catch {
                        // Non-fatal — keep file at original location, warn.
                        await MainActor.run {
                            statusLine = "Classify failed: \(error.localizedDescription) — kept in root folder."
                        }
                    }
                }

                await MainActor.run {
                    currentHandle = nil
                    lastOutputURL = finalURL
                    isRunning = false
                    progress = 1
                    if statusLine.hasPrefix("Classify failed") == false {
                        statusLine = "Done"
                    }
                    // Prefer yt-dlp metadata over filename parsing — gives us
                    // real Chinese/Japanese titles and the uploader as artist,
                    // so queue rows read "邓紫棋 — 光年之外" instead of
                    // "G.E.M._LIGHT_YEAR...HD-T4SimnaiktU".
                    let m = result.metadata
                    let artist = m.uploader ?? m.channel
                    if let track = library.addFile(url: finalURL, title: m.title, artist: artist) {
                        player.enqueue([track])
                        if chosenMode == .video {
                            VideoVibeWindowController.shared.show()
                        }
                    }
                    // Re-scan the Media catalog so the new file shows up
                    // in the left sidebar folder tree immediately — by
                    // default the catalog only auto-refreshes on window
                    // focus / every 15s, which left fresh downloads invisible
                    // until the user re-focused. Fires even when addFile
                    // returns nil (duplicate) because the file is still on
                    // disk and belongs in the folder tree.
                    appState.triggerRescanLibrary = true
                }
            } catch {
                await MainActor.run {
                    currentHandle = nil
                    isRunning = false
                    lastError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Search

    private var searchResultsList: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Search Results")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    searchResults = []
                    searchError = nil
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(searchResults) { r in
                        Button {
                            // Load the chosen result into the URL field and
                            // kick off the normal download path — same quality
                            // / mode / classify settings apply.
                            urlText = r.watchURL.absoluteString
                            searchResults = []
                            startDownload()
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: mode == .audio ? "music.note" : "play.rectangle")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(2)
                                        .truncationMode(.tail)
                                        .multilineTextAlignment(.leading)
                                    HStack(spacing: 6) {
                                        if let u = r.uploader {
                                            Text(u)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let d = r.duration {
                                            Text("·").foregroundStyle(.tertiary)
                                            Text(d).foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.system(size: 10))
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.04))
                        )
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func runSearch() {
        guard let binary = locator.binaryURL else { return }
        let q = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        searchError = nil
        searchResults = []
        Task {
            do {
                let results = try await YTDLPSearch.search(query: q, count: 8, binary: binary)
                searchResults = results
                if results.isEmpty {
                    searchError = "No results."
                }
            } catch {
                searchError = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func isChannelOrPlaylistURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        guard lower.contains("youtube.com") || lower.contains("youtu.be") else { return false }
        return lower.contains("/@")
            || lower.contains("/channel/")
            || lower.contains("/c/")
            || lower.contains("/user/")
            || lower.contains("/playlist")
    }
}
