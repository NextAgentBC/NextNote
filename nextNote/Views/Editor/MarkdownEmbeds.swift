import Foundation

/// Walk every `![alt](url)` in markdown source and swap it for a sentinel
/// that records embed kind (img / video / audio) + original src + alt.
/// The sentinel survives HTML escaping and is restored to a real
/// `<img>` / `<video>` / `<audio>` tag afterwards.
enum MarkdownEmbeds {
    static func replace(in text: String) -> String {
        let pattern = #"!\[(.*?)\]\(([^\)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var output = ""
        var cursor = 0
        for match in matches {
            let full = match.range
            if full.location > cursor {
                output += ns.substring(with: NSRange(location: cursor, length: full.location - cursor))
            }
            let alt = ns.substring(with: match.range(at: 1))
            let rawSrc = ns.substring(with: match.range(at: 2))
            let src = normalizeSrc(rawSrc)
            let kind = embedKind(for: rawSrc)
            output += "%%EMBED_\(kind)_START%%\(src)%%EMBED_ALT%%\(alt)%%EMBED_END%%"
            cursor = full.location + full.length
        }
        if cursor < ns.length {
            output += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return output
    }

    static func restore(in text: String) -> String {
        let pattern = #"%%EMBED_(IMG|VIDEO|AUDIO)_START%%(.+?)%%EMBED_ALT%%(.*?)%%EMBED_END%%"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var output = ""
        var cursor = 0
        for match in matches {
            let full = match.range
            if full.location > cursor {
                output += ns.substring(with: NSRange(location: cursor, length: full.location - cursor))
            }
            let kind = ns.substring(with: match.range(at: 1))
            let src = ns.substring(with: match.range(at: 2))
            let alt = ns.substring(with: match.range(at: 3))
            output += emitTag(kind: kind, src: src, alt: alt)
            cursor = full.location + full.length
        }
        if cursor < ns.length {
            output += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return output
    }

    static func embedKind(for rawSrc: String) -> String {
        let lower = rawSrc.lowercased()
        if let dot = lower.lastIndex(of: ".") {
            let ext = String(lower[lower.index(after: dot)...])
            if MediaKind.videoExts.contains(ext) { return "VIDEO" }
            if MediaKind.audioExts.contains(ext) { return "AUDIO" }
        }
        return "IMG"
    }

    static func normalizeSrc(_ raw: String) -> String {
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
        if raw.hasPrefix("/") { return "file://" + raw }
        return raw  // relative path — resolves against the HTML file's directory
    }

    static func emitTag(kind: String, src: String, alt: String) -> String {
        switch kind {
        case "VIDEO":
            return "<video controls preload=\"metadata\"><source src=\"\(src)\"></video>"
        case "AUDIO":
            return "<audio controls preload=\"metadata\"><source src=\"\(src)\"></audio>"
        default:
            return "<img src=\"\(src)\" alt=\"\(alt)\">"
        }
    }
}
