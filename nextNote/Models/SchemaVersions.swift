import SwiftData

// V1: legacy flat document model. Single @Model type.
// Future versions (V2+) will introduce the directory-backed Note model and
// migrate TextDocument rows out to disk. Defining the version now gives R2
// a named migration point.
enum NextNoteSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TextDocument.self]
    }
}

// V2 (R2): adds the disk-backed Note index alongside the legacy TextDocument.
// Keeping TextDocument in the schema lets legacy-mode users coexist with
// vault-mode users without a hard migration this release.
enum NextNoteSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TextDocument.self, Note.self]
    }
}

// V3: adds the Book library (EPUB reader) — Book + BookHighlight.
enum NextNoteSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TextDocument.self, Note.self, Book.self, BookHighlight.self]
    }
}

// V4: adds DownloadJob — persistent YouTube download history so jobs
// can resume after crash / quit and the user can browse / retry / clean
// up old downloads.
enum NextNoteSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TextDocument.self, Note.self, Book.self, BookHighlight.self, DownloadJob.self]
    }
}
