import Foundation
import SwiftData
import UniformTypeIdentifiers

/// App-wide queue + executor for YouTube downloads. Owns the SwiftData
/// `DownloadJob` records, runs at most one yt-dlp at a time, and feeds
/// progress updates back into the persisted job so the history view can
/// render live.
///
/// V1 scope: fire-and-forget submit, single-concurrency queue, cancel /
/// retry / delete. Audio-as-track-then-swap-to-video and crash-recovery
/// resume are layered on later.
@MainActor
final class DownloadJobCoordinator: ObservableObject {
    static let shared = DownloadJobCoordinator()

    /// Live yt-dlp handles keyed by job id, so cancel can reach them.
    private var liveHandles: [UUID: YTDLPHandle] = [:]
    /// Currently-executing job id (single-concurrency).
    private var running: UUID?

    /// Bound from ContentView so progress callbacks (which run on a
    /// non-main thread) can hop back here without capturing a
    /// non-Sendable ModelContext in their closure.
    private var modelContext: ModelContext?
    private weak var libraryRoots: LibraryRoots?
    private weak var appState: AppState?

    private init() {}

    /// Wire the coordinator to the app's environment. ContentView calls
    /// this once on first appear.
    func bind(modelContext: ModelContext, libraryRoots: LibraryRoots, appState: AppState) {
        self.modelContext = modelContext
        self.libraryRoots = libraryRoots
        self.appState = appState
    }

    // MARK: - Public API

    /// Submit a new job. Inserts a SwiftData record, kicks off execution
    /// if the queue is idle. Returns the new job's id.
    @discardableResult
    func submit(
        sourceURL: String,
        mode: DownloadJob.Mode,
        qualityRaw: String,
        saveTo: String,
        autoClassify: Bool,
        modelContext ctx: ModelContext,
        libraryRoots: LibraryRoots,
        appState: AppState,
        library: MediaLibrary,
        player: AmbientPlayer
    ) -> UUID {
        bind(modelContext: ctx, libraryRoots: libraryRoots, appState: appState)
        let job = DownloadJob(
            sourceURL: sourceURL,
            mode: mode,
            qualityRaw: qualityRaw,
            saveTo: saveTo,
            autoClassify: autoClassify
        )
        ctx.insert(job)
        saveOrLog(ctx)
        pumpQueue(library: library, player: player)
        return job.id
    }

    func cancel(_ jobID: UUID, modelContext: ModelContext) {
        liveHandles[jobID]?.cancel()
        liveHandles.removeValue(forKey: jobID)
        guard let job = fetch(jobID, in: modelContext) else { return }
        if job.status == .downloading || job.status == .transcoding || job.status == .queued {
            job.status = .canceled
            job.updatedAt = Date()
            saveOrLog(modelContext)
        }
        if running == jobID { running = nil }
    }

    func retry(
        _ jobID: UUID,
        modelContext ctx: ModelContext,
        libraryRoots: LibraryRoots,
        appState: AppState,
        library: MediaLibrary,
        player: AmbientPlayer
    ) {
        bind(modelContext: ctx, libraryRoots: libraryRoots, appState: appState)
        guard let job = fetch(jobID, in: ctx) else { return }
        job.status = .queued
        job.phase = .idle
        job.progress = 0
        job.statusLine = "Queued"
        job.errorMessage = nil
        job.updatedAt = Date()
        saveOrLog(ctx)
        pumpQueue(library: library, player: player)
    }

    func delete(_ jobID: UUID, modelContext: ModelContext) {
        cancel(jobID, modelContext: modelContext)
        guard let job = fetch(jobID, in: modelContext) else { return }
        modelContext.delete(job)
        saveOrLog(modelContext)
    }

    /// Progress callback target — called by the download Task back on
    /// main actor. UUID is Sendable so the call site can dispatch to us
    /// without capturing the ModelContext.
    func recordProgress(jobID: UUID, progress: Double, line: String) {
        guard let modelContext, let job = fetch(jobID, in: modelContext) else { return }
        if progress >= 0 { job.progress = progress }
        job.statusLine = line
        job.updatedAt = Date()
    }

    // MARK: - Queue

    /// Persist + log on failure. Replaces the previous `try? ctx.save()`
    /// pattern that silently dropped errors and let the UI render stale
    /// state.
    private func saveOrLog(_ ctx: ModelContext, function: StaticString = #function) {
        do {
            try ctx.save()
        } catch {
            print("[DownloadJobCoordinator.\(function)] save failed: \(error.localizedDescription)")
        }
    }

    private func fetch(_ id: UUID, in modelContext: ModelContext) -> DownloadJob? {
        let descriptor = FetchDescriptor<DownloadJob>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func nextQueuedJob(in modelContext: ModelContext) -> DownloadJob? {
        let queuedRaw = DownloadJob.Status.queued.rawValue
        let descriptor = FetchDescriptor<DownloadJob>(
            predicate: #Predicate { $0.statusRaw == queuedRaw },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func pumpQueue(library: MediaLibrary, player: AmbientPlayer) {
        guard running == nil else { return }
        guard let modelContext else { return }
        guard let job = nextQueuedJob(in: modelContext) else { return }
        let jobID = job.id
        running = jobID
        let handle = YTDLPHandle()
        liveHandles[jobID] = handle
        Task {
            await execute(jobID: jobID, handle: handle, library: library, player: player)
        }
    }

    // MARK: - Execution

    private func execute(
        jobID: UUID,
        handle: YTDLPHandle,
        library: MediaLibrary,
        player: AmbientPlayer
    ) async {
        defer {
            liveHandles.removeValue(forKey: jobID)
            if running == jobID { running = nil }
            // Pump again in case more jobs arrived while this one ran.
            pumpQueue(library: library, player: player)
        }

        guard let modelContext else { return }
        guard let job = fetch(jobID, in: modelContext) else { return }
        guard let binary = YTDLPLocator.shared.binaryURL,
              let folder = YTDLPLocator.shared.downloadFolderURL else {
            job.status = .failed
            job.errorMessage = "yt-dlp / download folder not configured."
            job.updatedAt = Date()
            saveOrLog(modelContext)
            return
        }

        job.status = .downloading
        job.phase = .download
        job.progress = 0
        job.statusLine = "Starting…"
        job.updatedAt = Date()
        saveOrLog(modelContext)

        let chosenMode: YTDLPDownloader.Mode = job.mode == .audio ? .audio : .video
        let quality = YTDLPDownloader.Quality(rawValue: job.qualityRaw) ?? .best
        let ffmpegURL = YTDLPLocator.shared.ffmpegURL
        let saveTo = job.saveToRaw
        let autoClassify = job.autoClassify
        let sourceURL = job.sourceURL

        do {
            let result = try await YTDLPDownloader.download(
                videoURL: sourceURL,
                mode: chosenMode,
                quality: quality,
                folder: folder,
                binary: binary,
                ffmpeg: ffmpegURL,
                handle: handle,
                progress: { p, line in
                    Task { @MainActor in
                        DownloadJobCoordinator.shared.recordProgress(jobID: jobID, progress: p, line: line)
                    }
                }
            )

            // Re-fetch — context may be different after the await.
            guard let job = fetch(jobID, in: modelContext) else { return }

            // Metadata write-through.
            job.title = result.metadata.title
            job.uploader = result.metadata.uploader
            job.statusLine = "Organizing…"
            saveOrLog(modelContext)

            var finalURL = result.outputURL

            if saveTo == "assets" {
                if let assetsRoot = libraryRoots?.ensureAssetsRoot() {
                    let bucket = chosenMode == .audio ? "audio" : "videos"
                    let bucketDir = assetsRoot.appendingPathComponent(bucket, isDirectory: true)
                    try? FileManager.default.createDirectory(at: bucketDir, withIntermediateDirectories: true)
                    let dest = FileDestinations.unique(for: finalURL.lastPathComponent, in: bucketDir)
                    do {
                        try FileManager.default.moveItem(at: finalURL, to: dest)
                        finalURL = dest
                    } catch {
                        job.statusLine = "Move to Assets failed: \(error.localizedDescription) — kept in download folder."
                    }
                }
            } else if autoClassify && (UserDefaults.standard.object(forKey: "media.autoOrganizeOnYTDownload") as? Bool ?? true) {
                job.phase = .classify
                job.statusLine = "Classifying…"
                saveOrLog(modelContext)
                let m = result.metadata
                let ctx = MediaCategorizer.Context(
                    uploader: m.uploader,
                    channel: m.channel,
                    categories: m.categories,
                    tags: m.tags,
                    playlist: m.playlist
                )
                let classifyRoot = libraryRoots?.mediaRoot ?? folder
                do {
                    finalURL = try await MediaCategorizer.organize(
                        url: finalURL,
                        underRoot: classifyRoot,
                        preferredTitle: m.title,
                        context: ctx.isEmpty ? nil : ctx
                    )
                } catch {
                    job.statusLine = "Classify failed: \(error.localizedDescription) — kept in root folder."
                }
            }

            // Register in MediaLibrary + enqueue.
            let artist = result.metadata.uploader ?? result.metadata.channel
            if let track = library.addFile(
                url: finalURL,
                title: result.metadata.title,
                artist: artist
            ) {
                player.enqueue([track])
                if chosenMode == .video {
                    VideoVibeWindowController.shared.show()
                }
            }
            appState?.triggerRescanLibrary = true

            job.finalPath = finalURL.path
            job.progress = 1
            job.phase = .idle
            job.status = .done
            job.completedAt = Date()
            job.updatedAt = Date()
            if !job.statusLine.hasPrefix("Classify failed") &&
               !job.statusLine.hasPrefix("Move to Assets failed") {
                job.statusLine = "Done"
            }
            saveOrLog(modelContext)

        } catch is CancellationError {
            // Already handled by cancel() — do nothing.
        } catch {
            if let job = fetch(jobID, in: modelContext) {
                job.status = .failed
                job.errorMessage = error.localizedDescription
                job.statusLine = error.localizedDescription
                job.phase = .idle
                job.updatedAt = Date()
                saveOrLog(modelContext)
            }
        }
    }
}
