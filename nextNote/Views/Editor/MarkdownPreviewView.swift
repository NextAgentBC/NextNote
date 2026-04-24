import SwiftUI
import WebKit

struct MarkdownPreviewView: View {
    let content: String
    /// Directory the preview should resolve relative links against. Typically
    /// the parent folder of the note. When nil, only absolute paths
    /// (`/Users/...`) and `http(s)://` URLs work — matches legacy behavior.
    var baseURL: URL? = nil

    var body: some View {
        MarkdownWebView(markdown: content, baseURL: baseURL)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - WebKit-based Markdown Preview

#if os(macOS)
struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let baseURL: URL?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        loadHTML(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadHTML(in: webView)
    }

    private func loadHTML(in webView: WKWebView) {
        loadPreview(webView: webView, markdown: markdown, baseURL: baseURL)
    }
}
#else
struct MarkdownWebView: UIViewRepresentable {
    let markdown: String
    let baseURL: URL?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        loadHTML(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        loadHTML(in: webView)
    }

    private func loadHTML(in webView: WKWebView) {
        loadPreview(webView: webView, markdown: markdown, baseURL: baseURL)
    }
}
#endif

/// Write the rendered HTML to the note's folder (as `.nextnote-preview.html`)
/// when a baseURL is known, so relative links in the markdown resolve against
/// their sibling files without needing a `<base href>` dance. Falls back to
/// the temp dir for legacy flat tabs.
private func loadPreview(webView: WKWebView, markdown: String, baseURL: URL?) {
    let html = wrapInHTML(markdown, baseURL: baseURL)
    let writeDir = baseURL ?? FileManager.default.temporaryDirectory
    let htmlFile = writeDir.appendingPathComponent(".nextnote-preview.html")
    do {
        try html.write(to: htmlFile, atomically: true, encoding: .utf8)
    } catch {
        // Fallback to temp if the vault dir is read-only for any reason.
        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("preview.html")
        try? html.write(to: fallback, atomically: true, encoding: .utf8)
        webView.loadFileURL(fallback, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        return
    }
    webView.loadFileURL(htmlFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
}

// MARK: - HTML Wrapper

private func wrapInHTML(_ markdown: String, baseURL: URL?) -> String {
    let htmlBody = simpleMarkdownToHTML(markdown)

    return """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <!-- KaTeX: $…$ inline and $$…$$ display math. Loaded from CDN; no
         network = math falls back to raw text and everything else still
         renders. -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css"
          integrity="sha384-nB0miv6/jRmo5UMMR1wu3Gz6NLsoTkbqJghGIsx//Rlm+ZU03BU6SQNC66uf4l5+" crossorigin="anonymous">
    <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"
            integrity="sha384-7zkQWkzuo3B5mTepMUcHkMB5jZaolc2xDwL6VFqjFALcbeS9Ggm/Yr2r3Dy4lfFg" crossorigin="anonymous"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js"
            integrity="sha384-43gviWU0YVjaDtb/GhzOouOXtZMP/7XUzwPTstBeZFe/+rCMvRwr4yROQP43s0Xk" crossorigin="anonymous"></script>
    <style>
        :root { color-scheme: light dark; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro", sans-serif;
            font-size: 16px; line-height: 1.6; padding: 20px;
            max-width: 800px; margin: 0 auto;
        }
        @media (prefers-color-scheme: dark) {
            :root { --text: #e0e0e0; --bg: #1e1e1e; --code-bg: #2d2d2d; --border: #404040; }
        }
        @media (prefers-color-scheme: light) {
            :root { --text: #1d1d1f; --bg: #ffffff; --code-bg: #f5f5f5; --border: #d1d1d6; }
        }
        body { background: var(--bg); color: var(--text); }
        h1 { font-size: 2em; border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
        h2 { font-size: 1.5em; border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
        h3 { font-size: 1.25em; }
        code {
            font-family: "SF Mono", Menlo, monospace; font-size: 0.9em;
            background: var(--code-bg); padding: 2px 6px; border-radius: 4px;
        }
        pre { background: var(--code-bg); padding: 16px; border-radius: 8px; overflow-x: auto; }
        pre code { padding: 0; background: none; }
        blockquote {
            border-left: 3px solid var(--border); margin-left: 0;
            padding-left: 16px; color: #888;
        }
        hr { border: none; border-top: 1px solid var(--border); margin: 24px 0; }
        a { color: #007AFF; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid var(--border); padding: 8px 12px; text-align: left; }
        th { background: var(--code-bg); }
        img { max-width: 100%; border-radius: 8px; margin: 8px 0; }
        video { max-width: 100%; border-radius: 8px; margin: 8px 0; }
        audio { width: 100%; margin: 8px 0; }
        .katex-display { overflow-x: auto; overflow-y: hidden; padding: 4px 0; }
    </style>
    </head>
    <body>
    \(htmlBody)
    <script>
      document.addEventListener("DOMContentLoaded", function() {
        if (typeof renderMathInElement !== "function") return;
        renderMathInElement(document.body, {
          delimiters: [
            { left: "$$", right: "$$", display: true },
            { left: "\\\\[", right: "\\\\]", display: true },
            { left: "$",  right: "$",  display: false },
            { left: "\\\\(", right: "\\\\)", display: false }
          ],
          throwOnError: false,
          ignoredTags: ["script", "noscript", "style", "textarea", "pre", "code"]
        });
      });
    </script>
    </body>
    </html>
    """
}

// MARK: - Markdown → HTML

private func simpleMarkdownToHTML(_ markdown: String) -> String {
    // Pull $$…$$ and $…$ math spans out before touching them — markdown's
    // *, _ rules would otherwise chew up subscripts / emphasis inside LaTeX.
    // KaTeX auto-render scans for the restored delimiters.
    let (protected, mathStash) = stashMath(markdown)
    var html = ""
    var inCodeBlock = false
    var codeLanguage = ""
    var inTable = false
    var tableRowIndex = 0
    let lines = protected.components(separatedBy: "\n")

    for line in lines {
        // Code blocks
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            if inCodeBlock {
                html += "</code></pre>\n"
                inCodeBlock = false
                codeLanguage = ""
            } else {
                codeLanguage = String(line.trimmingCharacters(in: .whitespaces).dropFirst(3))
                let langAttr = codeLanguage.isEmpty ? "" : " class=\"language-\(escapeHTML(codeLanguage))\""
                html += "<pre><code\(langAttr)>"
                inCodeBlock = true
            }
            continue
        }
        if inCodeBlock {
            html += escapeHTML(line) + "\n"
            continue
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Table detection: line starts with |
        if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
            let isSeparator = trimmed.replacingOccurrences(of: "|", with: "")
                .trimmingCharacters(in: .whitespaces)
                .allSatisfy { $0 == "-" || $0 == " " || $0 == ":" }

            if isSeparator { continue }

            if !inTable {
                html += "<table>\n"
                inTable = true
                tableRowIndex = 0
            }

            let cells = trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }

            let tag = tableRowIndex == 0 ? "th" : "td"
            html += "<tr>"
            for cell in cells {
                html += "<\(tag)>\(processInline(cell))</\(tag)>"
            }
            html += "</tr>\n"
            tableRowIndex += 1
            continue
        }

        if inTable {
            html += "</table>\n"
            inTable = false
            tableRowIndex = 0
        }

        if trimmed.hasPrefix("######") {
            html += "<h6>\(processInline(String(trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces))))</h6>\n"; continue
        } else if trimmed.hasPrefix("#####") {
            html += "<h5>\(processInline(String(trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces))))</h5>\n"; continue
        } else if trimmed.hasPrefix("####") {
            html += "<h4>\(processInline(String(trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces))))</h4>\n"; continue
        } else if trimmed.hasPrefix("###") {
            html += "<h3>\(processInline(String(trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces))))</h3>\n"; continue
        } else if trimmed.hasPrefix("##") {
            html += "<h2>\(processInline(String(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))))</h2>\n"; continue
        } else if trimmed.hasPrefix("# ") {
            html += "<h1>\(processInline(String(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))))</h1>\n"; continue
        }

        if trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) && trimmed.count >= 3 {
            html += "<hr>\n"; continue
        }
        if trimmed.hasPrefix("> ") {
            html += "<blockquote>\(processInline(String(trimmed.dropFirst(2))))</blockquote>\n"; continue
        }
        if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            html += "<li>☑ \(processInline(String(trimmed.dropFirst(6))))</li>\n"; continue
        }
        if trimmed.hasPrefix("- [ ] ") {
            html += "<li>☐ \(processInline(String(trimmed.dropFirst(6))))</li>\n"; continue
        }
        if let match = line.range(of: #"^(\s*)([-*+])\s+"#, options: .regularExpression) {
            html += "<li>\(processInline(String(line[match.upperBound...])))</li>\n"; continue
        }
        if let match = line.range(of: #"^(\s*)\d+\.\s+"#, options: .regularExpression) {
            html += "<li>\(processInline(String(line[match.upperBound...])))</li>\n"; continue
        }
        if trimmed.isEmpty { html += "<br>\n"; continue }
        html += "<p>\(processInline(line))</p>\n"
    }

    if inCodeBlock { html += "</code></pre>\n" }
    if inTable { html += "</table>\n" }
    return unstashMath(html, mathStash)
}

// MARK: - Math protection (KaTeX auto-render)
//
// Extract $$…$$ and $…$ spans into placeholder tokens before the markdown
// pass, restore them afterwards so the HTML delivered to KaTeX still has
// the original delimiters intact. Without this, `*`, `_`, `>` inside a
// formula get mangled into bold/italic/quote markup.
//
// Uses private-use Unicode markers so they can't collide with body text.

private let mathOpen = "\u{E000}MATH"
private let mathClose = "\u{E001}"

private func stashMath(_ input: String) -> (String, [String]) {
    var stash: [String] = []
    var out = ""
    let chars = Array(input)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        // Skip inline code spans — never treat `$` inside backticks as math.
        if c == "`" {
            let start = i
            var j = i + 1
            while j < chars.count && chars[j] != "`" { j += 1 }
            if j < chars.count { j += 1 }
            out.append(contentsOf: chars[start..<min(j, chars.count)])
            i = j
            continue
        }
        // $$ … $$ block math (non-greedy)
        if c == "$", i + 1 < chars.count, chars[i + 1] == "$" {
            let start = i
            var j = i + 2
            while j + 1 < chars.count && !(chars[j] == "$" && chars[j + 1] == "$") { j += 1 }
            if j + 1 < chars.count && chars[j] == "$" && chars[j + 1] == "$" {
                let content = String(chars[start...j + 1])
                let token = "\(mathOpen)\(stash.count)\(mathClose)"
                stash.append(content)
                out.append(token)
                i = j + 2
                continue
            }
        }
        // $ … $ inline math
        if c == "$" {
            let start = i
            // Skip escaped \$
            if i > 0, chars[i - 1] == "\\" { out.append(c); i += 1; continue }
            var j = i + 1
            // Don't treat standalone $ in text as math — require balanced close on the same line, no whitespace immediately after opening.
            if j < chars.count, chars[j] == " " || chars[j] == "\t" || chars[j] == "\n" {
                out.append(c); i += 1; continue
            }
            while j < chars.count && chars[j] != "\n" && chars[j] != "$" { j += 1 }
            if j < chars.count, chars[j] == "$", j > start + 1 {
                let content = String(chars[start...j])
                let token = "\(mathOpen)\(stash.count)\(mathClose)"
                stash.append(content)
                out.append(token)
                i = j + 1
                continue
            }
        }
        out.append(c)
        i += 1
    }
    return (out, stash)
}

private func unstashMath(_ html: String, _ stash: [String]) -> String {
    var out = html
    for (idx, raw) in stash.enumerated() {
        let token = "\(mathOpen)\(idx)\(mathClose)"
        out = out.replacingOccurrences(of: token, with: raw)
    }
    return out
}

private func processInline(_ text: String) -> String {
    var result = text

    // Extract ![alt](url) BEFORE escaping so the url/alt can be shielded
    // from HTML escaping and later turned into <img>/<video>/<audio>
    // depending on the file extension. Accepts any url form: /absolute,
    // http(s)://, or relative path (relative resolves against the HTML
    // file's own directory — which is the note's folder when we wrote it
    // there in loadPreview).
    result = replaceEmbeds(in: result)

    // Links BEFORE escaping
    result = result.replacingOccurrences(
        of: #"\[([^\]]+)\]\(([^\)]+)\)"#,
        with: "%%LINK_START%%$2%%LINK_TEXT%%$1%%LINK_END%%",
        options: .regularExpression)

    result = escapeHTML(result)

    // Restore embeds + links from placeholders. The embed placeholder
    // encodes kind + src directly so the final tag depends on the file
    // extension captured earlier.
    result = restoreEmbeds(in: result)
    result = result.replacingOccurrences(of: "%%LINK_START%%", with: "<a href=\"")
    result = result.replacingOccurrences(of: "%%LINK_TEXT%%", with: "\">")
    result = result.replacingOccurrences(of: "%%LINK_END%%", with: "</a>")

    // Bold
    result = result.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
    result = result.replacingOccurrences(of: #"__(.+?)__"#, with: "<strong>$1</strong>", options: .regularExpression)
    // Italic
    result = result.replacingOccurrences(of: #"\*(.+?)\*"#, with: "<em>$1</em>", options: .regularExpression)
    result = result.replacingOccurrences(of: #"_(.+?)_"#, with: "<em>$1</em>", options: .regularExpression)
    // Strikethrough
    result = result.replacingOccurrences(of: #"~~(.+?)~~"#, with: "<del>$1</del>", options: .regularExpression)
    // Inline code
    result = result.replacingOccurrences(of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)

    return result
}

/// Walk every `![alt](url)` and swap it out for a sentinel that records the
/// embed kind (img / video / audio) plus the original src and alt. The
/// sentinel is restored after HTML escaping has happened.
private func replaceEmbeds(in text: String) -> String {
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

private func restoreEmbeds(in text: String) -> String {
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
        output += emitEmbedTag(kind: kind, src: src, alt: alt)
        cursor = full.location + full.length
    }
    if cursor < ns.length {
        output += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
    }
    return output
}

private func embedKind(for rawSrc: String) -> String {
    let lower = rawSrc.lowercased()
    if let dot = lower.lastIndex(of: ".") {
        let ext = String(lower[lower.index(after: dot)...])
        if MediaKind.videoExts.contains(ext) { return "VIDEO" }
        if MediaKind.audioExts.contains(ext) { return "AUDIO" }
    }
    return "IMG"
}

private func normalizeSrc(_ raw: String) -> String {
    if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
    if raw.hasPrefix("/") { return "file://" + raw }
    return raw  // relative path — resolves against the HTML file's directory
}

private func emitEmbedTag(kind: String, src: String, alt: String) -> String {
    switch kind {
    case "VIDEO":
        return "<video controls preload=\"metadata\"><source src=\"\(src)\"></video>"
    case "AUDIO":
        return "<audio controls preload=\"metadata\"><source src=\"\(src)\"></audio>"
    default:
        return "<img src=\"\(src)\" alt=\"\(alt)\">"
    }
}

private func escapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}
