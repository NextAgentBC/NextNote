import Foundation

/// Build the full HTML document that the WKWebView preview loads. KaTeX
/// is loaded from CDN; if no network is available, math falls back to
/// raw text and everything else still renders. Light/dark theming via
/// `prefers-color-scheme`.
enum MarkdownHTMLWrapper {
    static func wrap(_ markdown: String, baseURL: URL?) -> String {
        var htmlBody = MarkdownToHTML.render(markdown)
        // Rewrite every local asset URL (`file://` / absolute paths / relatives)
        // to `nextnote-asset://localhost<abs-path>` so they resolve through
        // PreviewAssetSchemeHandler — the preview page itself loads with an
        // `https://www.youtube-nocookie.com` origin so YouTube iframes work,
        // which makes the page cross-origin to `file://` and blocks direct
        // file-URL subresource loads. http(s)/data/asset URLs pass through.
        htmlBody = rewriteAssetURLs(in: htmlBody, baseURL: baseURL)
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
            a.wikilink {
                background: rgba(0, 122, 255, 0.10);
                padding: 1px 4px;
                border-radius: 4px;
                text-decoration: none;
            }
            a.wikilink:hover { background: rgba(0, 122, 255, 0.20); }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid var(--border); padding: 8px 12px; text-align: left; }
            th { background: var(--code-bg); }
            img { max-width: 100%; border-radius: 8px; margin: 8px 0; }
            video { max-width: 100%; border-radius: 8px; margin: 8px 0; }
            audio { width: 100%; margin: 8px 0; }
            iframe { max-width: 100%; border-radius: 8px; margin: 8px 0; display: block; aspect-ratio: 16 / 9; height: auto; }
            .katex-display { overflow-x: auto; overflow-y: hidden; padding: 4px 0; }
        </style>
        </head>
        <body>
        \(htmlBody)
        <script>
          // Force first-frame paint on every video so the preview shows a
          // cover image instead of a black box. Seek to 0.1s once metadata
          // arrives, then unmute and let the user control playback.
          document.addEventListener("DOMContentLoaded", function() {
            document.querySelectorAll("video.nn-video").forEach(function(v) {
              var seeked = false;
              v.addEventListener("loadedmetadata", function() {
                if (seeked) return;
                seeked = true;
                try { v.currentTime = Math.min(0.1, (v.duration || 1) * 0.01); } catch (e) {}
              });
              v.addEventListener("seeked", function once() {
                v.removeEventListener("seeked", once);
                v.muted = false;
              });
            });
          });
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

    private static let srcAttrRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"src=["']([^"']+)["']"#, options: [.caseInsensitive])
    }()

    private static func rewriteAssetURLs(in html: String, baseURL: URL?) -> String {
        guard let regex = srcAttrRegex else { return html }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return html }

        let baseDir: URL? = {
            guard let baseURL else { return nil }
            return baseURL.hasDirectoryPath ? baseURL : baseURL.deletingLastPathComponent()
        }()

        var output = ""
        var cursor = 0
        for match in matches {
            let full = match.range
            let src = ns.substring(with: match.range(at: 1))
            if full.location > cursor {
                output += ns.substring(with: NSRange(location: cursor, length: full.location - cursor))
            }
            let rewritten = rewriteToAssetScheme(src, baseDir: baseDir) ?? src
            output += "src=\"\(rewritten)\""
            cursor = full.location + full.length
        }
        if cursor < ns.length {
            output += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return output
    }

    private static func rewriteToAssetScheme(_ src: String, baseDir: URL?) -> String? {
        let lower = src.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") ||
           lower.hasPrefix("data:") || lower.hasPrefix("\(PreviewAssetSchemeHandler.scheme):") {
            return nil
        }
        let absPath: String
        if lower.hasPrefix("file://") {
            guard let url = URL(string: src) else { return nil }
            absPath = url.path
        } else if src.hasPrefix("/") {
            absPath = src
        } else {
            guard let baseDir else { return nil }
            absPath = baseDir.appendingPathComponent(src).path
        }
        let encoded = absPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? absPath
        return "\(PreviewAssetSchemeHandler.scheme)://localhost\(encoded)"
    }
}
