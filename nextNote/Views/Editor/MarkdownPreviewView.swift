import SwiftUI
import WebKit

/// Renders markdown content into a WKWebView. Pure-function HTML
/// generation lives in `MarkdownToHTML`, `MarkdownEmbeds`, and
/// `MarkdownHTMLWrapper`. This file is just the SwiftUI / NSViewRep
/// glue + the disk write that gives KaTeX + relative `<img>` srcs a
/// real file URL to resolve against.
struct MarkdownPreviewView: View {
    let content: String
    /// Directory the preview should resolve relative links against.
    /// Typically the parent folder of the note. When nil, only absolute
    /// paths (`/Users/...`) and `http(s)://` URLs work — matches legacy
    /// behavior.
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
        loadPreview(in: webView, markdown: markdown, baseURL: baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadPreview(in: webView, markdown: markdown, baseURL: baseURL)
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
        loadPreview(in: webView, markdown: markdown, baseURL: baseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        loadPreview(in: webView, markdown: markdown, baseURL: baseURL)
    }
}
#endif

/// Write the rendered HTML to the note's folder (as
/// `.nextnote-preview.html`) when a baseURL is known, so relative links
/// in the markdown resolve against their sibling files without needing a
/// `<base href>` dance. Falls back to the temp dir for legacy flat tabs.
private func loadPreview(in webView: WKWebView, markdown: String, baseURL: URL?) {
    let html = MarkdownHTMLWrapper.wrap(markdown, baseURL: baseURL)
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
