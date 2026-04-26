import Foundation

/// Pure string helpers for building track display titles. Used by the
/// MediaLibrary on insert and by yt-dlp metadata backfill.
enum TrackTitleFormatter {
    /// "邓紫棋 — 光年之外" when both parts known; fall back progressively
    /// to title-only, then to the cleaned-up filename.
    static func displayTitle(explicit: String?, artist: String?, fallbackURL: URL) -> String {
        let clean = { (s: String?) -> String? in
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        let t = clean(explicit)
        let a = clean(artist)
        if let a, let t { return "\(a) — \(t)" }
        if let t { return t }
        if let a { return a }
        // Last-ditch: filename, but strip the " [videoId]" yt-dlp suffix so
        // folder-scan imports of existing downloads still look readable.
        let raw = fallbackURL.deletingPathExtension().lastPathComponent
        return stripYouTubeIDSuffix(raw)
    }

    /// Matches a trailing ` [xxxxxxxxxxx]` where the id is 11 chars of
    /// YouTube's base64-ish alphabet. Non-YT filenames pass through.
    static func stripYouTubeIDSuffix(_ s: String) -> String {
        let pattern = #"\s*\[[A-Za-z0-9_-]{11}\]\s*$"#
        if let range = s.range(of: pattern, options: .regularExpression) {
            return String(s[..<range.lowerBound])
        }
        return s
    }
}
