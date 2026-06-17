import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves local files referenced by the markdown preview. The preview
/// itself loads via `loadHTMLString` with an `https://www.youtube-nocookie.com`
/// baseURL so YouTube iframes negotiate their embed origin (a `file://`
/// origin trips YouTube Error 153 / "Video player configuration error" —
/// WebKit strips the Referer on file:// pages and YouTube's embed page
/// rejects). That makes the preview cross-origin to `file://`, blocking
/// `<img src="file:///…">` etc. — so we rewrite every local asset URL in
/// the rendered HTML to `nextnote-asset://localhost<abs-path>` and serve
/// the bytes here, with `Access-Control-Allow-Origin: *` so the
/// cross-origin fetch is allowed.
///
/// Security: only paths under `projectRoot` or the per-note `noteDir` are
/// served. Requests outside those roots fail with `.noPermissionsToReadFile`
/// so a crafted note cannot exfiltrate arbitrary local files.
final class PreviewAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "nextnote-asset"

    /// The current project folder — set by ContentView when a project opens
    /// or switches. Acts as the primary trust boundary for asset requests.
    nonisolated(unsafe) static var projectRoot: URL?

    /// Directory of the note being previewed. Allows images embedded in
    /// notes opened outside the project (e.g. from a pinned folder) to
    /// resolve correctly.
    private let noteDir: URL?

    init(noteDir: URL?) {
        self.noteDir = noteDir
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let target = URL(fileURLWithPath: url.path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let targetPath = target.path

        let allowedRoots: [String] = [Self.projectRoot, noteDir]
            .compactMap { $0 }
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }

        let isAllowed = allowedRoots.contains { root in
            targetPath == root || targetPath.hasPrefix(root + "/")
        }

        guard isAllowed else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }

        let fileURL = URL(fileURLWithPath: url.path)
        do {
            let data = try Data(contentsOf: fileURL)
            let ext = fileURL.pathExtension
            let mime = UTType(filenameExtension: ext)?.preferredMIMEType
                ?? "application/octet-stream"
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": mime,
                    "Content-Length": "\(data.count)",
                    "Access-Control-Allow-Origin": "*"
                ]
            )!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Synchronous load — nothing to cancel.
    }
}
