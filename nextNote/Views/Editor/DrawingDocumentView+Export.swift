import SwiftUI
#if os(macOS)
import AppKit

// Export the drawing to a multi-page PDF. Renders from live on-screen state —
// the same stroke geometry, page backgrounds, placed screenshots and (loaded)
// video thumbnails the user sees — so the PDF is a faithful snapshot. One
// drawing page maps to one PDF page (`DrawingPDFRenderer`).
extension DrawingDocumentView {
    func exportPDF() {
        saveNow()   // flush latest edits + ensure assets are on disk

        let renderPages: [DrawingPDFRenderer.Page] = pages.indices.map { i in
            let vp = pages[i]
            let h = pageRenderHeight(i)
            let size = CGSize(width: pageWidth, height: h)

            // bgCache[i] is populated only when the page has a background, so
            // this matches the on-screen render exactly (which draws bgCache[i]).
            let bg: CGImage? = bgCache[i].flatMap(cgImage)
            let images: [DrawingPDFRenderer.Placed] = vp.images.compactMap { img in
                guard let cg = imgCache[img.path].flatMap(cgImage) else { return nil }
                return .init(image: cg, rect: CGRect(x: img.x, y: img.y, width: img.w, height: img.h))
            }
            let videos: [DrawingPDFRenderer.Video] = vp.videos.map { v in
                .init(thumb: thumbCache[v.youtubeID].flatMap(cgImage),
                      rect: CGRect(x: v.x, y: v.y, width: v.w, height: v.h),
                      linkURL: URL(string: "https://www.youtube.com/watch?v=\(v.youtubeID)"))
            }
            let strokes: [DrawingPDFRenderer.Stroke] = vp.strokes.map { s in
                let (r, g, b, a) = s.color.rgbaComponents
                let color = CGColor(srgbRed: r, green: g, blue: b, alpha: a)
                if s.points.count <= 1 {
                    let dot = s.points.first.map {
                        CGRect(x: $0.x - s.width / 2, y: $0.y - s.width / 2, width: s.width, height: s.width)
                    }
                    return .init(path: nil, dot: dot, color: color, width: s.width)
                }
                return .init(path: Self.cgSmoothedPath(s.points), dot: nil, color: color, width: s.width)
            }
            return .init(size: size, background: bg, images: images, videos: videos, strokes: strokes)
        }

        guard let data = DrawingPDFRenderer.makePDFData(pages: renderPages) else {
            saveError = "Couldn't render the PDF"; return
        }

        let panel = NSSavePanel()
        panel.title = "Export Drawing as PDF"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(suggestedExportName).pdf"
        panel.directoryURL = fileURL.deletingLastPathComponent()
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            do {
                try data.write(to: dest, options: .atomic)
                NSWorkspace.shared.activateFileViewerSelecting([dest])
                saveError = nil
            } catch {
                saveError = "PDF export failed: \(error.localizedDescription)"
            }
        }
    }

    /// Default file name for the exported PDF: the drawing's base name, minus
    /// the leading dot of a hidden markdown-note Draw-layer sidecar.
    private var suggestedExportName: String {
        var base = fileURL.deletingPathExtension().lastPathComponent
        if base.hasPrefix(".") { base.removeFirst() }
        return base.isEmpty ? "Drawing" : base.replacingOccurrences(of: "/", with: "-")
    }

    private func cgImage(_ ns: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: ns.size)
        return ns.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
#else
extension DrawingDocumentView {
    func exportPDF() {}
}
#endif
