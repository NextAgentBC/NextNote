import Foundation

/// Recognised playable media file categories. Anything that isn't text-like
/// and lives in the vault is routed through here.
enum MediaKind: String {
    case video
    case audio

    static let videoExts: Set<String> = ["mp4", "mov", "m4v", "webm"]
    static let audioExts: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "ogg"]

    static func from(url: URL) -> MediaKind? {
        from(ext: url.pathExtension)
    }

    static func from(ext: String) -> MediaKind? {
        let e = ext.lowercased()
        if videoExts.contains(e) { return .video }
        if audioExts.contains(e) { return .audio }
        return nil
    }

    /// All extensions the vault scanner should index.
    static var allExts: Set<String> { videoExts.union(audioExts) }

    var iconName: String {
        switch self {
        case .video: return "play.rectangle"
        case .audio: return "waveform"
        }
    }
}
