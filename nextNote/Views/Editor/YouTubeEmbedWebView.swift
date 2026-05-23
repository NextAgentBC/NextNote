import SwiftUI
import WebKit

/// Inline YouTube player backed by a WKWebView loading the standard iframe
/// embed. Used by the drawing canvas when a placed video card is tapped to
/// play. (The markdown preview embeds the same iframe directly in its own
/// WKWebView, so this path is already known to work in a non-sandboxed,
/// network-enabled build.)
struct YouTubeEmbedWebView {
    let youtubeID: String

    @MainActor
    fileprivate func makeWebView() -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let wv = WKWebView(frame: .zero, configuration: cfg)
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
        iframe{border:0;width:100%;height:100%;display:block}</style>
        </head><body>
        <iframe src="https://www.youtube-nocookie.com/embed/\(youtubeID)?autoplay=1&playsinline=1&rel=0"
          allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
          allowfullscreen></iframe>
        </body></html>
        """
        // baseURL is the embedder ORIGIN YouTube checks. As of 2025 YouTube
        // returns "Error 152 (embedder.identity.denied)" when the origin is
        // youtube.com itself — using the privacy-enhanced youtube-nocookie.com
        // origin is the accepted fix (see youtube_player_flutter #1086).
        wv.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
        return wv
    }
}

#if os(macOS)
import AppKit

extension YouTubeEmbedWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView() }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
import UIKit

extension YouTubeEmbedWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView() }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
