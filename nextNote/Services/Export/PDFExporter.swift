import Foundation
import WebKit
#if os(macOS)
import AppKit
#endif

/// Render markdown (with drawings, images, KaTeX) to a PDF using the same
/// pipeline as the on-screen preview. The WKWebView is held until the
/// nav-delegate fires `didFinish`, then `createPDF` writes the result.
enum PDFExporter {
    /// Loads the rendered HTML in an offscreen WKWebView, waits for the
    /// page to finish (including a small delay so KaTeX can typeset), then
    /// writes the PDF to `destination`.
    @MainActor
    static func export(markdown: String,
                       baseURL: URL?,
                       destination: URL,
                       completion: @escaping (Result<URL, Error>) -> Void) {
        let html = MarkdownHTMLWrapper.wrap(markdown, baseURL: baseURL)
        let writeDir = baseURL ?? FileManager.default.temporaryDirectory
        let htmlFile = writeDir.appendingPathComponent(".nextnote-pdf-export.html")
        do {
            try html.write(to: htmlFile, atomically: true, encoding: .utf8)
        } catch {
            completion(.failure(error)); return
        }

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 1100), configuration: config)
        let coordinator = ExportCoordinator(webView: webView,
                                            htmlFile: htmlFile,
                                            destination: destination,
                                            completion: completion)
        webView.navigationDelegate = coordinator
        Self.holder = coordinator
        webView.loadFileURL(htmlFile, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    /// Strong reference to keep the webView + delegate alive until export
    /// finishes. Cleared in the completion path.
    @MainActor private static var holder: ExportCoordinator?

    private final class ExportCoordinator: NSObject, WKNavigationDelegate {
        let webView: WKWebView
        let htmlFile: URL
        let destination: URL
        let completion: (Result<URL, Error>) -> Void
        private var done = false

        init(webView: WKWebView,
             htmlFile: URL,
             destination: URL,
             completion: @escaping (Result<URL, Error>) -> Void) {
            self.webView = webView
            self.htmlFile = htmlFile
            self.destination = destination
            self.completion = completion
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Give KaTeX a beat to typeset before snapshotting.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.snapshot()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            finish(.failure(error))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            finish(.failure(error))
        }

        @MainActor
        private func snapshot() {
            guard !done else { return }
            let pdfConfig = WKPDFConfiguration()
            // Capture the entire scrollable content, not just the visible rect.
            webView.evaluateJavaScript("[document.body.scrollWidth, document.body.scrollHeight]") { [weak self] result, _ in
                guard let self else { return }
                if let arr = result as? [CGFloat], arr.count == 2 {
                    pdfConfig.rect = CGRect(x: 0, y: 0, width: arr[0], height: arr[1])
                }
                self.webView.createPDF(configuration: pdfConfig) { pdfResult in
                    switch pdfResult {
                    case .success(let data):
                        do {
                            try data.write(to: self.destination, options: .atomic)
                            self.finish(.success(self.destination))
                        } catch {
                            self.finish(.failure(error))
                        }
                    case .failure(let err):
                        self.finish(.failure(err))
                    }
                }
            }
        }

        private func finish(_ result: Result<URL, Error>) {
            guard !done else { return }
            done = true
            try? FileManager.default.removeItem(at: htmlFile)
            DispatchQueue.main.async {
                self.completion(result)
                MainActor.assumeIsolated { PDFExporter.holder = nil }
            }
        }
    }
}

#if os(macOS)
extension ContentView {
    func exportActiveNoteAsPDF() {
        guard let tab = appState.activeTab else { return }
        let markdown = tab.document.content
        let baseURL: URL? = {
            guard preferences.vaultMode,
                  let rel = appState.vaultPath(forTabId: tab.id),
                  let fileURL = vault.url(for: rel) else { return nil }
            return fileURL.deletingLastPathComponent()
        }()
        let suggestedName: String = {
            let raw = tab.document.title.isEmpty ? "Untitled" : tab.document.title
            return raw.replacingOccurrences(of: "/", with: "-")
        }()

        let panel = NSSavePanel()
        panel.title = "Export Note as PDF"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(suggestedName).pdf"
        if let baseURL { panel.directoryURL = baseURL }
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            Task { @MainActor in
                PDFExporter.export(markdown: markdown, baseURL: baseURL, destination: dest) { result in
                    switch result {
                    case .success(let url):
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    case .failure(let err):
                        appState.lastSaveError = "PDF export failed: \(err.localizedDescription)"
                    }
                }
            }
        }
    }
}
#endif
