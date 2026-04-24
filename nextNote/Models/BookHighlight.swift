import Foundation
import SwiftData

// User highlight / annotation inside a Book chapter. Range is expressed as
// character offsets into the chapter's plain-text projection; the web view
// resolves offsets back to DOM ranges on load.
@Model
final class BookHighlight {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var chapterHref: String
    var chapterIndex: Int
    var selectedText: String
    var rangeStart: Int
    var rangeEnd: Int
    var note: String
    var color: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        bookID: UUID,
        chapterHref: String,
        chapterIndex: Int,
        selectedText: String,
        rangeStart: Int,
        rangeEnd: Int,
        note: String = "",
        color: String = "yellow"
    ) {
        self.id = id
        self.bookID = bookID
        self.chapterHref = chapterHref
        self.chapterIndex = chapterIndex
        self.selectedText = selectedText
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.note = note
        self.color = color
        self.createdAt = Date()
    }
}
