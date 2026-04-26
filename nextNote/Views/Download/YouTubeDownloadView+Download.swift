import SwiftUI

extension YouTubeDownloadView {
    var canDownload: Bool {
        !isRunning
            && locator.binaryURL != nil
            && locator.downloadFolderURL != nil
            && !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func startDownload() {
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
                // bookmark aimed at the final path from the start. Prefer
                // the Media library root over the yt-dlp download folder so
                // the classifier creates <mediaRoot>/<Artist>/... subdirs.
                // Otherwise auto-classified files land in sibling folders
                // next to mediaRoot and never appear in the left sidebar.
                var finalURL = result.outputURL
                let destination: SaveDestination = await MainActor.run { saveTo }
                if destination == .assets {
                    // Assets: route into the kind-specific subfolder so it
                    // shows up under the right category, alongside Finder
                    // imports.
                    let assetsRoot: URL? = await MainActor.run {
                        libraryRoots.ensureAssetsRoot()
                    }
                    if let assetsRoot {
                        let src = result.outputURL
                        let bucket = chosenMode == .audio ? "audio" : "videos"
                        let bucketDir = assetsRoot.appendingPathComponent(bucket, isDirectory: true)
                        try? FileManager.default.createDirectory(
                            at: bucketDir, withIntermediateDirectories: true
                        )
                        let dest = FileDestinations.unique(for: src.lastPathComponent, in: bucketDir)
                        do {
                            try FileManager.default.moveItem(at: src, to: dest)
                            finalURL = dest
                        } catch {
                            await MainActor.run {
                                statusLine = "Move to Assets failed: \(error.localizedDescription) — kept in download folder."
                            }
                        }
                    }
                } else if autoClassify {
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
                    // Prefer yt-dlp metadata over filename parsing — gives
                    // real Chinese/Japanese titles and the uploader as artist.
                    let m = result.metadata
                    let artist = m.uploader ?? m.channel
                    if let track = library.addFile(url: finalURL, title: m.title, artist: artist) {
                        player.enqueue([track])
                        if chosenMode == .video {
                            VideoVibeWindowController.shared.show()
                        }
                    }
                    // Re-scan the Media catalog so the new file shows up in
                    // the left sidebar folder tree immediately.
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
}
