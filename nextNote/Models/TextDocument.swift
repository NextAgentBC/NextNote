import Foundation
import SwiftData

@Model
final class TextDocument {
    var id: UUID
    var title: String
    var content: String
    var fileTypeRaw: String
    var createdAt: Date
    var modifiedAt: Date
    var tags: [String]
    var category: String?
    var isFavorite: Bool
    var iCloudSynced: Bool

    var fileType: FileType {
        get { FileType(rawValue: fileTypeRaw) ?? .txt }
        set { fileTypeRaw = newValue.rawValue }
    }

    var wordCount: Int {
        let words = content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return words.count
    }

    var characterCount: Int {
        content.count
    }

    var lineCount: Int {
        content.isEmpty ? 0 : content.components(separatedBy: .newlines).count
    }

    init(
        title: String = "Untitled",
        content: String = "",
        fileType: FileType = .txt
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.fileTypeRaw = fileType.rawValue
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.tags = []
        self.category = nil
        self.isFavorite = false
        self.iCloudSynced = false
    }
}

// (DocumentVersion model removed — was dead code in PureText, never instantiated.)
