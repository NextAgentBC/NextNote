import Foundation

// Single source of truth for sidebar grouping. Given a URL / extension,
// classify into one of the top-level sections the library sidebar renders.
enum FileCategory: String, CaseIterable {
    case note
    case book
    case music
    case video
    case image
    case other

    static func classify(url: URL) -> FileCategory {
        classify(ext: url.pathExtension)
    }

    static func classify(ext: String) -> FileCategory {
        let e = ext.lowercased()
        if e == "epub" { return .book }
        if e == "md" || e == "markdown" || e == "txt" { return .note }
        if MediaKind.audioExts.contains(e) { return .music }
        if MediaKind.videoExts.contains(e) { return .video }
        if Self.imageExts.contains(e) { return .image }
        return .other
    }

    static let imageExts: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp",
        "heic", "heif", "bmp", "tiff", "svg",
    ]
}
