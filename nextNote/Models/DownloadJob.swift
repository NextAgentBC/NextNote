import Foundation
import SwiftData

/// Persistent record of a YouTube download. Lives across app launches so
/// in-flight downloads can resume after a crash / quit, and so the user
/// has a history view to browse / retry / clean up old jobs.
@Model
final class DownloadJob {
    @Attribute(.unique) var id: UUID
    var sourceURL: String
    var title: String?
    var uploader: String?
    /// Raw value of `Mode` — kept as String for SwiftData compatibility.
    var modeRaw: String
    /// Raw value of `Quality`.
    var qualityRaw: String
    /// "media" or "assets" — destination root for the final file.
    var saveToRaw: String
    var autoClassify: Bool
    /// Raw value of `Status`.
    var statusRaw: String
    /// Raw value of `Phase`.
    var phaseRaw: String
    /// 0..1 within the current phase.
    var progress: Double
    var statusLine: String
    var rawAudioPath: String?
    var rawVideoPath: String?
    var finalPath: String?
    var bytesDownloaded: Int64
    var totalBytes: Int64?
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    enum Mode: String, Codable, CaseIterable, Identifiable {
        case audio
        case video
        var id: String { rawValue }
    }

    enum Status: String, Codable, CaseIterable, Identifiable {
        case queued
        case downloading
        case transcoding
        case done
        case failed
        case canceled
        var id: String { rawValue }
    }

    enum Phase: String, Codable, CaseIterable {
        case download
        case merge
        case classify
        case move
        case idle
    }

    init(
        id: UUID = UUID(),
        sourceURL: String,
        mode: Mode,
        qualityRaw: String,
        saveTo: String,
        autoClassify: Bool
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.title = nil
        self.uploader = nil
        self.modeRaw = mode.rawValue
        self.qualityRaw = qualityRaw
        self.saveToRaw = saveTo
        self.autoClassify = autoClassify
        self.statusRaw = Status.queued.rawValue
        self.phaseRaw = Phase.idle.rawValue
        self.progress = 0
        self.statusLine = ""
        self.rawAudioPath = nil
        self.rawVideoPath = nil
        self.finalPath = nil
        self.bytesDownloaded = 0
        self.totalBytes = nil
        self.errorMessage = nil
        self.createdAt = Date()
        self.updatedAt = Date()
        self.completedAt = nil
    }

    var mode: Mode {
        get { Mode(rawValue: modeRaw) ?? .audio }
        set { modeRaw = newValue.rawValue }
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }

    var phase: Phase {
        get { Phase(rawValue: phaseRaw) ?? .idle }
        set { phaseRaw = newValue.rawValue }
    }

    var finalURL: URL? {
        guard let p = finalPath else { return nil }
        return URL(fileURLWithPath: p)
    }
}
