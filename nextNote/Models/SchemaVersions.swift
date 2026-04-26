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

// V5: Book gains optional `kindRaw` (epub | pdf) so PDF files can live
// in the same library + reader pipeline as EPUBs. Field is optional so
// V4 records decode without migration.
enum NextNoteSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TextDocument.self, Note.self, Book.self, BookHighlight.self, DownloadJob.self]
    }
}

// V6: Book gains `aiSuggestionData` (optional Data, nil by default) and
// `suggestedFolder` (optional String). Both optional so V5 records decode
// without a heavyweight migration.
enum NextNoteSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TextDocument.self, Note.self, Book.self, BookHighlight.self, DownloadJob.self]
    }
}

// V7: Book gains `documentID` (optional UUID, FK to Postgres vector DB) and
// `embeddingStatusRaw` (String, default "pending"). Both have default values
// so V6 records coexist without migration.
enum NextNoteSchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)
    static var models: [any PersistentModel.Type] {
        [TextDocument.self, Note.self, Book.self, BookHighlight.self, DownloadJob.self]
    }
}
