import SwiftUI
import WebKit

extension Notification.Name {
    /// Posted when the user clicks a `[[wiki-link]]` in the markdown
    /// preview. `userInfo["target"]` carries the raw target string from
    /// the link's `nextnote://wiki?target=…` query.
    static let nextNoteWikiLinkClicked = Notification.Name("nextnote.wikilink.clicked")
}

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
@MainActor
final class MarkdownPreviewCoordinator: NSObject, WKNavigationDelegate {
    var pending: DispatchWorkItem?
    var lastMarkdown: String?
    var lastBaseURL: URL?

    // The deinit dropped its cancel() — `pending` was non-Sendable, which
    // Swift 6 flags inside an NSObject-derived nonisolated deinit. The
    // work-item already captures `webView` weakly, so a stray firing after
    // teardown just bails out cheaply.

    // Intercept clicks on `[[wiki-link]]` anchors — those render with a
    // `nextnote://wiki?target=…` href. Everything else (file:// preview
    // assets, http(s) links) is allowed through.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           url.scheme == "nextnote",
           url.host == "wiki",
           let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let target = comps.queryItems?.first(where: { $0.name == "target" })?.value {
            NotificationCenter.default.post(
                name: .nextNoteWikiLinkClicked,
                object: nil,
                userInfo: ["target": target]
            )
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

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
        let webView = WKWebView(frame: .zero, configuration: makePreviewConfig(noteDir: baseURL))
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
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
        let webView = WKWebView(frame: .zero, configuration: makePreviewConfig(noteDir: baseURL))
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.loadImmediately(in: webView, markdown: markdown, baseURL: baseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.schedule(in: webView, markdown: markdown, baseURL: baseURL)
    }
}
#endif

private func makePreviewConfig(noteDir: URL?) -> WKWebViewConfiguration {
    let config = WKWebViewConfiguration()
    config.setURLSchemeHandler(PreviewAssetSchemeHandler(noteDir: noteDir),
                               forURLScheme: PreviewAssetSchemeHandler.scheme)
    return config
}

/// Load the rendered HTML via `loadHTMLString` with an https `baseURL` so
/// embedded YouTube iframes don't trip Error 153 (WebKit strips the Referer
/// on file:// pages; YouTube's embed endpoint rejects). Local assets are
/// served by `PreviewAssetSchemeHandler` via the custom `nextnote-asset://`
/// scheme registered on the config — `MarkdownHTMLWrapper` rewrites every
/// local `src` to that scheme before this point.
private func loadPreview(in webView: WKWebView, markdown: String, baseURL: URL?) {
    let html = MarkdownHTMLWrapper.wrap(markdown, baseURL: baseURL)
    let previewOrigin = URL(string: "https://www.youtube-nocookie.com/__nextnote_preview__/")!
    webView.loadHTMLString(html, baseURL: previewOrigin)
}
