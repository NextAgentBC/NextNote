import Foundation
import AVFoundation

// Thin wrapper around AVAssetExportSession for the two video ops we expose in
// the media tab: trim a single asset to a time range, and concatenate a list
// of assets in order. Callers drive progress via the provided closure.
enum VideoExporter {

    enum ExportError: LocalizedError {
        case noExportSession
        case noVideoTrack
        case failed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noExportSession: return "Could not create export session."
            case .noVideoTrack: return "No video track found."
            case .failed(let msg): return "Export failed: \(msg)"
            case .cancelled: return "Export cancelled."
            }
        }
    }

    /// Export `asset` clipped to `timeRange` to `destination` as .mp4.
    static func trim(
        asset: AVAsset,
        timeRange: CMTimeRange,
        to destination: URL,
        preset: String = AVAssetExportPresetHighestQuality,
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ExportError.noExportSession
        }
        session.outputURL = destination
        session.outputFileType = .mp4
        session.timeRange = timeRange
        session.shouldOptimizeForNetworkUse = true

        try await run(session: session, progress: progress)
    }

    /// Export `asset` with the audio track(s) stripped. Video-only output at
    /// the source's full duration.
    static func stripAudio(
        asset: AVAsset,
        to destination: URL,
        preset: String = AVAssetExportPresetHighestQuality,
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws {
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let duration = try await asset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: duration)
        guard let src = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }
        try videoTrack?.insertTimeRange(range, of: src, at: .zero)
        videoTrack?.preferredTransform = try await src.load(.preferredTransform)

        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw ExportError.noExportSession
        }
        session.outputURL = destination
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        try await run(session: session, progress: progress)
    }

    /// Concatenate `urls` in order, audio+video, and export to `destination` as .mp4.
    static func concat(
        urls: [URL],
        to destination: URL,
        preset: String = AVAssetExportPresetHighestQuality,
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws {
        guard !urls.isEmpty else { throw ExportError.noVideoTrack }

        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: duration)

            if let v = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack?.insertTimeRange(range, of: v, at: cursor)
                // First asset's transform wins — good enough for "same source"
                // concat; rotated mixes would need per-segment instructions.
                if cursor == .zero {
                    videoTrack?.preferredTransform = try await v.load(.preferredTransform)
                }
            } else {
                throw ExportError.noVideoTrack
            }

            if let a = try await asset.loadTracks(withMediaType: .audio).first {
                try audioTrack?.insertTimeRange(range, of: a, at: cursor)
            }

            cursor = CMTimeAdd(cursor, duration)
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw ExportError.noExportSession
        }
        session.outputURL = destination
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        try await run(session: session, progress: progress)
    }

    // MARK: - Internal

    // AVAssetExportSession is not Sendable; wrap in an @unchecked box so the
    // polling Task can read `progress` across actor boundaries. Progress is
    // thread-safe per Apple's AVFoundation docs.
    private final class SessionBox: @unchecked Sendable {
        let session: AVAssetExportSession
        init(_ s: AVAssetExportSession) { self.session = s }
    }

    private static func run(
        session: AVAssetExportSession,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let box = SessionBox(session)
        let progressTask = Task.detached {
            while !Task.isCancelled {
                let p = box.session.progress
                progress(Double(p))
                if p >= 1.0 { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { progressTask.cancel() }

        // exportAsynchronously is the macOS 14-compatible entry point.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            box.session.exportAsynchronously {
                cont.resume()
            }
        }

        switch session.status {
        case .completed:
            progress(1.0)
        case .cancelled:
            throw ExportError.cancelled
        case .failed:
            throw ExportError.failed(session.error?.localizedDescription ?? "unknown")
        default:
            throw ExportError.failed("unexpected status \(session.status.rawValue)")
        }
    }
}
