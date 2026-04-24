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
        contentHash: String
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
    }
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
struct BookTOCEntry: Codable, Hashable, Identifiable {
    var title: String
    var href: String
    var children: [BookTOCEntry]
    var id: String { href + "|" + title }
}

// Spine entry — persisted inside Book.spineJSON.
struct BookSpineEntry: Codable, Hashable {
    var href: String
    var mediaType: String
}
