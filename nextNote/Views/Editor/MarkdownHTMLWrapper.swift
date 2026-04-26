import Foundation

/// Build the full HTML document that the WKWebView preview loads. KaTeX
/// is loaded from CDN; if no network is available, math falls back to
/// raw text and everything else still renders. Light/dark theming via
/// `prefers-color-scheme`.
enum MarkdownHTMLWrapper {
    static func wrap(_ markdown: String, baseURL: URL?) -> String {
        let htmlBody = MarkdownToHTML.render(markdown)
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
}
