import Foundation
import SwiftData

// Metadata index for a vault-backed .epub book. The .epub archive itself lives
// at <vault>/Books/<slug>/<file>.epub. Unzipped working copy lives in
// Caches/Books/<id>/ and is regenerated on demand.
//
// TOC + spine are denormalized to JSON so the reader can boot without
// re-parsing the OPF on every open.
@Model
final class Book {
    @Attribute(.unique) var id: UUID
    var relativePath: String
    var title: String
    var author: String?
    var publisher: String?
    var language: String?
    var coverRelativePath: String?

    var tocJSON: Data
    var spineJSON: Data
    var opfRelativePath: String

    var lastChapterIndex: Int
    var lastScrollRatio: Double
    var addedAt: Date
    var lastOpenedAt: Date?
    var contentHash: String

    var fontSize: Double
    var themeRaw: String
    /// "epub" | "pdf". Optional + defaulted so books imported under V4
    /// (epub-only) keep decoding cleanly.
    var kindRaw: String?

    /// AI-suggested folder name. Nil until categorized.
    var suggestedFolder: String?

    /// FK to Postgres documents.id in the vector DB. Set after embedding succeeds.
    var documentID: UUID?

    /// Embedding pipeline state.
    var embeddingStatusRaw: String = EmbeddingStatus.pending.rawValue

    init(
        id: UUID = UUID(),
        relativePath: String,
        title: String,
        author: String? = nil,
        publisher: String? = nil,
        language: String? = nil,
        coverRelativePath: String? = nil,
        tocJSON: Data,
        spineJSON: Data,
        opfRelativePath: String,
        contentHash: String,
        kind: BookKind = .epub
    ) {
        self.id = id
        self.relativePath = relativePath
        self.title = title
        self.author = author
        self.publisher = publisher
        self.language = language
        self.coverRelativePath = coverRelativePath
        self.tocJSON = tocJSON
        self.spineJSON = spineJSON
        self.opfRelativePath = opfRelativePath
        self.lastChapterIndex = 0
        self.lastScrollRatio = 0
        self.addedAt = Date()
        self.lastOpenedAt = nil
        self.contentHash = contentHash
        self.fontSize = 17
        self.themeRaw = BookTheme.light.rawValue
        self.kindRaw = kind.rawValue
    }

    var kind: BookKind {
        // Default to epub for legacy V4 records that pre-date this field.
        BookKind(rawValue: kindRaw ?? "epub") ?? .epub
    }

    var embeddingStatus: EmbeddingStatus {
        get { EmbeddingStatus(rawValue: embeddingStatusRaw) ?? .pending }
        set { embeddingStatusRaw = newValue.rawValue }
    }

}

enum BookKind: String, Codable, CaseIterable {
    case epub
    case pdf
}

enum BookTheme: String, CaseIterable, Identifiable {
    case light, sepia, dark
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .light: return "Light"
        case .sepia: return "Sepia"
        case .dark: return "Dark"
        }
    }
}

// Serialized TOC entry — persisted inside Book.tocJSON.
//
// `spineIndex` is resolved at import time by matching the entry's
// absolute file URL against spine[].absolute URL (path equality).
// Doing this once at import lets every chapter jump be a plain
// integer lookup, sidestepping the brittle string-format matching
// that Calibre / foliate / Apple Books all gave up on years ago.
//
// `href` is kept around for debug + the Refresh TOC fallback path.
// `anchor` is the URL fragment (id) when the TOC links to a
// mid-chapter section; nil for whole-chapter entries.
struct BookTOCEntry: Codable, Hashable, Identifiable {
    var title: String
    var href: String
    var children: [BookTOCEntry]
    var spineIndex: Int?
    var anchor: String?
    var id: String { href + "|" + title }

    // Manual Codable so older books (saved before spineIndex/anchor
    // existed) still decode without nil-key errors.
    enum CodingKeys: String, CodingKey {
        case title, href, children, spineIndex, anchor
    }

    init(title: String, href: String, children: [BookTOCEntry],
         spineIndex: Int? = nil, anchor: String? = nil) {
        self.title = title
        self.href = href
        self.children = children
        self.spineIndex = spineIndex
        self.anchor = anchor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try c.decode(String.self, forKey: .title)
        self.href = try c.decode(String.self, forKey: .href)
        self.children = try c.decodeIfPresent([BookTOCEntry].self, forKey: .children) ?? []
        self.spineIndex = try c.decodeIfPresent(Int.self, forKey: .spineIndex)
        self.anchor = try c.decodeIfPresent(String.self, forKey: .anchor)
    }
}

enum EmbeddingStatus: String {
    case pending, embedded, failed
}

// Spine entry — persisted inside Book.spineJSON.
struct BookSpineEntry: Codable, Hashable {
    var href: String
    var mediaType: String
}
