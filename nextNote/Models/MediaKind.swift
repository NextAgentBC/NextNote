import Foundation

/// Recognised playable media file categories. Anything that isn't text-like
/// and lives in the vault is routed through here.
enum MediaKind: String {
    case video
    case audio
    case image

    static let videoExts: Set<String> = ["mp4", "mov", "m4v", "webm"]
    static let audioExts: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "ogg"]
    /// Image formats the asset library + editor accept. SVG / TIFF left out —
    /// WKWebView renders them, but preview sizing gets awkward.
    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp"]

    static func from(url: URL) -> MediaKind? {
        from(ext: url.pathExtension)
    }

    static func from(ext: String) -> MediaKind? {
        let e = ext.lowercased()
        if videoExts.contains(e) { return .video }
        if audioExts.contains(e) { return .audio }
        if imageExts.contains(e) { return .image }
        return nil
    }

    /// All extensions the vault scanner should index.
    static var allExts: Set<String> { videoExts.union(audioExts).union(imageExts) }

    var iconName: String {
        switch self {
        case .video: return "play.rectangle"
        case .audio: return "waveform"
        case .image: return "photo"
        }
    }
}
