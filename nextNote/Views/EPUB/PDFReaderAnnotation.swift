#if os(macOS)
import SwiftUI
import PDFKit

// Tool model + the PDFView subclass that actually performs ink editing.
// Split out of PDFReaderView so the SwiftUI shell stays compact and the
// AppKit drawing surface lives next to the overlay it relies on.

// MARK: - Annotation tool model

enum PDFAnnTool: String, CaseIterable, Identifiable {
    case hand, pen, highlighter, eraser
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .hand:        return "hand.raised"
        case .pen:         return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser:      return "eraser"
        }
    }
}

enum PDFInkColor: String, CaseIterable, Identifiable {
    case red, blue, black, green, yellow
    var id: String { rawValue }
    private var base: NSColor {
        switch self {
        case .red:    return .systemRed
        case .blue:   return .systemBlue
        case .black:  return .black
        case .green:  return .systemGreen
        case .yellow: return .systemYellow
        }
    }
    func nsColor(forTool tool: PDFAnnTool) -> NSColor {
        tool == .highlighter ? base.withAlphaComponent(0.3) : base
    }
}

// MARK: - Annotating PDFView

/// PDFView subclass that turns mouse drags into ink `PDFAnnotation`s on the
/// page under the cursor. Coordinate conversion uses PDFView's own
/// `page(for:nearest:)` + `convert(_:to:)` so points land in page space (no
/// manual Y-flip). When `tool == .hand` it defers to PDFView for normal
/// scroll / text selection.
final class AnnotatingPDFView: PDFView {
    var tool: PDFAnnTool = .hand
    var inkColor: NSColor = .systemRed
    var lineWidth: CGFloat = 2
    var onEdited: (() -> Void)?

    private struct StrokeRecord {
        let page: PDFPage
        let annotation: PDFAnnotation
        let bbox: CGRect
    }
    /// Session-scoped record of ink we added, with tight bounding boxes — used
    /// by the eraser to hit-test (annotations carry full-page bounds so we
    /// can't hit-test by `annotation.bounds`). Strokes from a previously-saved
    /// file aren't in this list (erasing those is a later enhancement).
    private var records: [StrokeRecord] = []
    private var drawingPage: PDFPage?
    private var pagePoints: [CGPoint] = []
    // Live preview: an overlay subview strokes the in-progress line in view
    // coords (instant feedback); the real PDFAnnotation is committed on mouseUp.
    private var overlayPoints: [CGPoint] = []
    private var strokeOverlay: StrokeOverlayView?

    private func pagePoint(for event: NSEvent, page forcedPage: PDFPage? = nil) -> (PDFPage, CGPoint)? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = forcedPage ?? self.page(for: viewPoint, nearest: true) else { return nil }
        return (page, convert(viewPoint, to: page))
    }

    override func mouseDown(with event: NSEvent) {
        switch tool {
        case .hand:
            super.mouseDown(with: event)
        case .pen, .highlighter:
            guard let (page, p) = pagePoint(for: event) else { return }
            drawingPage = page
            pagePoints = [p]
            overlayPoints = [convert(event.locationInWindow, from: nil)]
            updateOverlay()
        case .eraser:
            if let (page, p) = pagePoint(for: event) { eraseHit(p, on: page) }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        switch tool {
        case .hand:
            super.mouseDragged(with: event)
        case .pen, .highlighter:
            guard let page = drawingPage, let (_, p) = pagePoint(for: event, page: page) else { return }
            pagePoints.append(p)
            overlayPoints.append(convert(event.locationInWindow, from: nil))
            updateOverlay()
        case .eraser:
            if let (page, p) = pagePoint(for: event) { eraseHit(p, on: page) }
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch tool {
        case .hand:
            super.mouseUp(with: event)
        case .pen, .highlighter:
            if let page = drawingPage, !pagePoints.isEmpty {
                commitInk(on: page)
                onEdited?()
            }
            drawingPage = nil
            pagePoints = []
            overlayPoints = []
            strokeOverlay?.viewPoints = []
            strokeOverlay?.needsDisplay = true
        case .eraser:
            break
        }
    }

    private func updateOverlay() {
        if strokeOverlay == nil {
            let ov = StrokeOverlayView(frame: bounds)
            ov.autoresizingMask = [.width, .height]
            addSubview(ov)
            strokeOverlay = ov
        }
        guard let ov = strokeOverlay else { return }
        if ov.superview !== self || subviews.last !== ov {
            ov.removeFromSuperview()
            addSubview(ov)  // keep on top
        }
        ov.frame = bounds
        ov.strokeColor = inkColor
        ov.strokeWidth = max(1, lineWidth * scaleFactor)
        ov.viewPoints = overlayPoints
        ov.needsDisplay = true
    }

    private func commitInk(on page: PDFPage) {
        // Tight bounds + a path expressed RELATIVE to those bounds. A full
        // `.mediaBox`-bounds ink annotation carrying absolute page-coordinate
        // points strokes live but VANISHES on the next redraw under macOS 26 —
        // PDFKit stopped building an appearance stream for that shape, so the
        // ink is gone the moment the live overlay clears on mouseUp. Sizing the
        // annotation to the stroke and offsetting the path into the annotation's
        // local space yields a stable appearance that survives scroll/redraw.
        let box = boundingBox(pagePoints, pad: max(lineWidth, 8))
        let annotation = PDFAnnotation(bounds: box, forType: .ink, withProperties: nil)
        let border = PDFBorder()
        border.lineWidth = lineWidth
        annotation.border = border
        annotation.color = inkColor

        let origin = box.origin
        let local = pagePoints.map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if local.count == 1 {
            let f = local[0]
            path.appendOval(in: CGRect(x: f.x - lineWidth / 2, y: f.y - lineWidth / 2,
                                       width: lineWidth, height: lineWidth))
        } else {
            path.move(to: local[0])
            for q in local.dropFirst() { path.line(to: q) }
        }
        annotation.add(path)
        page.addAnnotation(annotation)
        records.append(StrokeRecord(page: page, annotation: annotation, bbox: box))
    }

    private func eraseHit(_ p: CGPoint, on page: PDFPage) {
        let hits = records.filter { $0.page === page && $0.bbox.contains(p) }
        guard !hits.isEmpty else { return }
        for rec in hits { page.removeAnnotation(rec.annotation) }
        let removed = Set(hits.map { ObjectIdentifier($0.annotation) })
        records.removeAll { removed.contains(ObjectIdentifier($0.annotation)) }
        onEdited?()
    }

    private func boundingBox(_ points: [CGPoint], pad: CGFloat) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX - pad, y: minY - pad,
                      width: (maxX - minX) + pad * 2, height: (maxY - minY) + pad * 2)
    }
}

/// Transparent overlay that strokes the in-progress line in the PDFView's
/// own (view) coordinates for instant feedback. Returns nil from hitTest so
/// all mouse events still reach the PDFView underneath.
final class StrokeOverlayView: NSView {
    var viewPoints: [CGPoint] = []
    var strokeColor: NSColor = .systemRed
    var strokeWidth: CGFloat = 2

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard !viewPoints.isEmpty else { return }
        let path = NSBezierPath()
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if viewPoints.count == 1 {
            let f = viewPoints[0]
            let r = CGRect(x: f.x - strokeWidth/2, y: f.y - strokeWidth/2, width: strokeWidth, height: strokeWidth)
            strokeColor.setFill()
            NSBezierPath(ovalIn: r).fill()
        } else {
            path.move(to: viewPoints[0])
            for p in viewPoints.dropFirst() { path.line(to: p) }
            strokeColor.setStroke()
            path.stroke()
        }
    }
}
#endif
