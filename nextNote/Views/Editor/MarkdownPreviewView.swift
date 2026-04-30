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

/// Debounces `updateNSView` / `updateUIView` reload calls. Editor keystrokes
/// publish a new `markdown` value on every change, which would re-render the
/// entire HTML and force a `loadFileURL` per character — visible as keystroke
/// lag in split / preview mode. Coalesce reloads to one per ~350ms idle.
final class MarkdownPreviewCoordinator {
    var pending: DispatchWorkItem?
    var lastMarkdown: String?
    var lastBaseURL: URL?

    deinit { pending?.cancel() }

    func schedule(in webView: WKWebView, markdown: String, baseURL: URL?) {
        if markdown == lastMarkdown && baseURL == lastBaseURL { return }
        lastMarkdown = markdown
        lastBaseURL = baseURL
        pending?.cancel()
        let work = DispatchWorkItem { [weak webView] in
            guard let webView else { return }
            loadPreview(in: webView, markdown: markdown, baseURL: baseURL)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func loadImmediately(in webView: WKWebView, markdown: String, baseURL: URL?) {
        pending?.cancel()
        lastMarkdown = markdown
        lastBaseURL = baseURL
        loadPreview(in: webView, markdown: markdown, baseURL: baseURL)
    }
}

#if os(macOS)
struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    let baseURL: URL?

    func makeCoordinator() -> MarkdownPreviewCoordinator { MarkdownPreviewCoordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.loadImmediately(in: webView, markdown: markdown, baseURL: baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.schedule(in: webView, markdown: markdown, baseURL: baseURL)
    }
}
#else
struct MarkdownWebView: UIViewRepresentable {
    let markdown: String
    let baseURL: URL?

    func makeCoordinator() -> MarkdownPreviewCoordinator { MarkdownPreviewCoordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        context.coordinator.loadImmediately(in: webView, markdown: markdown, baseURL: baseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.schedule(in: webView, markdown: markdown, baseURL: baseURL)
    }
}
#endif

/// Write the rendered HTML to a per-note file under the system temp dir.
/// `MarkdownHTMLWrapper.wrap` injects `<base href="…/">` so relative
/// asset paths still resolve against the note's vault folder without
/// having to drop a `.nextnote-preview.html` next to the note itself.
private func loadPreview(in webView: WKWebView, markdown: String, baseURL: URL?) {
    let html = MarkdownHTMLWrapper.wrap(markdown, baseURL: baseURL)
    let key = previewFileKey(for: baseURL)
    let writeDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("nextnote-previews", isDirectory: true)
    try? FileManager.default.createDirectory(at: writeDir, withIntermediateDirectories: true)
    let htmlFile = writeDir.appendingPathComponent("preview-\(key).html")
    do {
        try html.write(to: htmlFile, atomically: true, encoding: .utf8)
    } catch {
        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("preview.html")
        try? html.write(to: fallback, atomically: true, encoding: .utf8)
        webView.loadFileURL(fallback, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        return
    }
    webView.loadFileURL(htmlFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
}

private func previewFileKey(for baseURL: URL?) -> String {
    guard let baseURL else { return "default" }
    return String(baseURL.absoluteString.hash & 0x7fffffff, radix: 16)
}
