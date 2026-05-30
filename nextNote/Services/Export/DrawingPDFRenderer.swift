import Foundation
#if os(macOS)
import AppKit
import CoreGraphics
import PDFKit

/// Pure CoreGraphics renderer that turns a `.nndraw` drawing into a multi-page,
/// vector PDF. One `DrawingDoc` page → one PDF page (Letter @ 72 dpi by default;
/// pages with a full-bleed background grow to the background's aspect, matching
/// `DrawingDocumentView.pageRenderHeight`).
///
/// Inputs are fully resolved primitives (CGImage / CGPath / CGColor) so this
/// file stays free of SwiftUI and view state — `DrawingDocumentView+Export`
/// gathers the live on-screen state and hands it over. Ink smoothing lives with
/// the on-screen renderer (`cgSmoothedPath`); here we only stroke the paths,
/// which keeps the exported ink pixel-faithful to the canvas.
enum DrawingPDFRenderer {
    /// One placed bitmap (pasted screenshot) stretched into `rect` (page points,
    /// top-left origin) — matches the canvas's `.resizable()` (non-aspect) frame.
    struct Placed { var image: CGImage; var rect: CGRect }
    /// A placed YouTube card: its thumbnail if loaded, else a dark placeholder.
    /// `linkURL`, if set, becomes a clickable PDF link annotation over the card.
    struct Video { var thumb: CGImage?; var rect: CGRect; var linkURL: URL? }
    /// One ink stroke, pre-resolved: a smoothed multi-point `path`, OR a single
    /// `dot` (tap) when the stroke has ≤1 point — mirroring the on-screen path.
    struct Stroke { var path: CGPath?; var dot: CGRect?; var color: CGColor; var width: CGFloat }
    struct Page {
        var size: CGSize            // page box in points (top-left origin space)
        var background: CGImage?    // full-bleed page background, if any
        var images: [Placed]
        var videos: [Video]
        var strokes: [Stroke]
    }

    /// Render `pages` to in-memory PDF data. Returns nil only if a CG context
    /// can't be created. Call on the main actor (CGImages come from the view).
    static func makePDFData(pages: [Page]) -> Data? {
        let out = NSMutableData()
        guard let consumer = CGDataConsumer(data: out as CFMutableData) else { return nil }
        var firstBox = CGRect(origin: .zero,
                              size: pages.first?.size ?? CGSize(width: DrawingDoc.letterWidth,
                                                                height: DrawingDoc.letterHeight))
        guard let ctx = CGContext(consumer: consumer, mediaBox: &firstBox, nil) else { return nil }

        for page in pages {
            var box = CGRect(origin: .zero, size: page.size)
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size) as CFData]
            ctx.beginPDFPage(info as CFDictionary)

            // Paper.
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(box)

            // Flip into a top-left origin so page coordinates match the canvas.
            ctx.saveGState()
            ctx.translateBy(x: 0, y: page.size.height)
            ctx.scaleBy(x: 1, y: -1)

            if let bg = page.background {
                draw(bg, in: CGRect(origin: .zero, size: page.size), ctx: ctx)
            }
            for placed in page.images {
                draw(placed.image, in: placed.rect, ctx: ctx)
            }
            for video in page.videos {
                drawVideoCard(video, ctx: ctx)
            }
            for s in page.strokes {
                drawStroke(s, ctx: ctx)
            }

            ctx.restoreGState()
            ctx.endPDFPage()
        }

        ctx.closePDF()
        let base = out as Data

        // Overlay clickable link annotations on any video cards (PDFKit pass —
        // CGContext can't add link rects). The drawn card stays as a visual for
        // non-interactive viewers; this just makes it tappable.
        guard pages.contains(where: { $0.videos.contains { $0.linkURL != nil } }),
              let doc = PDFDocument(data: base) else { return base }
        for (i, page) in pages.enumerated() {
            guard let pdfPage = doc.page(at: i) else { continue }
            for video in page.videos {
                guard let url = video.linkURL else { continue }
                // PDF annotation bounds are bottom-left origin; our rects are top-left.
                let bounds = CGRect(x: video.rect.minX,
                                    y: page.size.height - video.rect.maxY,
                                    width: video.rect.width, height: video.rect.height)
                let ann = PDFAnnotation(bounds: bounds, forType: .link, withProperties: nil)
                ann.action = PDFActionURL(url: url)
                pdfPage.addAnnotation(ann)
            }
        }
        return doc.dataRepresentation() ?? base
    }

    // MARK: - Primitives

    /// Draw a CGImage right-side-up into `rect` of a top-left-origin context.
    /// (CGImages are bottom-up, so we locally re-flip around the rect.)
    private static func draw(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    /// Aspect-fill a CGImage into `rect`, clipped to the rect (used for the
    /// video thumbnail, which the canvas draws with `.fill`).
    private static func drawAspectFill(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        guard iw > 0, ih > 0, rect.width > 0, rect.height > 0 else { return }
        let scale = max(rect.width / iw, rect.height / ih)
        let w = iw * scale, h = ih * scale
        let target = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.clip()
        draw(image, in: target, ctx: ctx)
        ctx.restoreGState()
    }

    /// A placed video: thumbnail (or a dark card) with a play triangle, so the
    /// static export still reads as an embedded video at the right spot/size.
    private static func drawVideoCard(_ video: Video, ctx: CGContext) {
        let rect = video.rect
        let rounded = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        if let thumb = video.thumb {
            drawAspectFill(thumb, in: rect, ctx: ctx)
        } else {
            ctx.saveGState()
            ctx.addPath(rounded); ctx.clip()
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
            ctx.fill(rect)
            ctx.restoreGState()
        }
        // Play triangle, centered.
        let s = min(rect.width, rect.height) * 0.22
        let cx = rect.midX, cy = rect.midY
        let tri = CGMutablePath()
        tri.move(to: CGPoint(x: cx - s * 0.5, y: cy - s * 0.6))
        tri.addLine(to: CGPoint(x: cx - s * 0.5, y: cy + s * 0.6))
        tri.addLine(to: CGPoint(x: cx + s * 0.7, y: cy))
        tri.closeSubpath()
        ctx.addPath(tri)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        ctx.fillPath()
    }

    private static func drawStroke(_ s: Stroke, ctx: CGContext) {
        if let dot = s.dot {
            ctx.setFillColor(s.color)
            ctx.fillEllipse(in: dot)
            return
        }
        guard let path = s.path else { return }
        ctx.addPath(path)
        ctx.setStrokeColor(s.color)
        ctx.setLineWidth(s.width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }
}
#endif
