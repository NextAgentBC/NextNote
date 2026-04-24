import Foundation
import SwiftData

// Metadata index row for a vault-backed .md file. Source of truth is the
// file on disk; this row caches hash, mtime, and AI summaries so we don't
// re-spend Gemini calls on unchanged notes.
//
// `relativePath` is the unique key. Rename on disk = delete + insert (NoteIndex
// reconciles this on rescan).
@Model
final class Note {
    @Attribute(.unique) var relativePath: String
    var displayName: String
    var contentHash: String
    var fileModifiedAt: Date
    var indexedAt: Date

    // AI (R4+R5) — leaf summary cache, keyed to contentHash so a stale
    // summary is trivially detectable.
    var lastAISummaryAt: Date?
    var cachedSummary: String?
    var cachedSummaryForHash: String?

    init(
        relativePath: String,
        displayName: String,
        contentHash: String,
        fileModifiedAt: Date
    ) {
        self.relativePath = relativePath
        self.displayName = displayName
        self.contentHash = contentHash
        self.fileModifiedAt = fileModifiedAt
        self.indexedAt = Date()
    }
}
