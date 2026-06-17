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

/// PDFView subclass that turns mouse drags into ink on the page under the
/// cursor. Coordinate conversion uses PDFView's own `page(for:nearest:)` +
/// `convert(_:to:)` so points land in page space (no manual Y-flip). When
/// `tool == .hand` it defers to PDFView for normal scroll / text selection.
///
/// Display vs. persistence are deliberately decoupled. macOS 26's PDFKit no
/// longer renders a programmatically-added `.ink` `PDFAnnotation` on screen
/// (no redraw force — `setNeedsDisplay`, `layoutDocumentView`, even a full
/// document detach/re-attach — brings it back; the appearance stream is never
/// drawn). So **display** is done by `StrokeOverlayView`, which paints the ink
/// ourselves over the page; the `PDFAnnotation` is still added so the stroke
/// **persists** into the file on `PDFDocument.write` (and shows in Preview /
/// other readers). The overlay re-projects page-space strokes to view space on
/// every scroll / zoom so the ink tracks the page.
final class AnnotatingPDFView: PDFView {
    var tool: PDFAnnTool = .hand
    var inkColor: NSColor = .systemRed
    var lineWidth: CGFloat = 2
    var onEdited: (() -> Void)?

    private struct StrokeRecord {
        let page: PDFPage
        let annotation: PDFAnnotation
        let bbox: CGRect           // page coords — eraser hit-test
        let points: [CGPoint]      // page coords — overlay re-projection
        let color: NSColor
        let width: CGFloat
    }
    /// Session-scoped record of ink we added. Drives both the eraser hit-test
    /// and the overlay's on-screen rendering. Strokes from a previously-saved
    /// file aren't in this list (erasing / re-rendering those is a later
    /// enhancement — they render via PDFKit's own loaded-annotation path).
    private var records: [StrokeRecord] = []
    private var drawingPage: PDFPage?
    private var pagePoints: [CGPoint] = []
    // Live in-progress stroke, in view coords (instant feedback).
    private var overlayPoints: [CGPoint] = []
    private var strokeOverlay: StrokeOverlayView?
    private var observingScroll = false

    // MARK: Scroll / zoom observation — keep the overlay aligned to the page.

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !observingScroll else { return }
        observingScroll = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(refreshOverlay),
                       name: .PDFViewScaleChanged, object: self)
        nc.addObserver(self, selector: #selector(refreshOverlay),
                       name: .PDFViewPageChanged, object: self)
        if let clip = documentScrollView()?.contentView {
            clip.postsBoundsChangedNotifications = true
            nc.addObserver(self, selector: #selector(refreshOverlay),
                           name: NSView.boundsDidChangeNotification, object: clip)
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// PDFView hosts its scrolling document content in an internal NSScrollView.
    private func documentScrollView() -> NSScrollView? {
        func find(_ v: NSView) -> NSScrollView? {
            for sub in v.subviews {
                if let sv = sub as? NSScrollView { return sv }
                if let nested = find(sub) { return nested }
            }
            return nil
        }
        return find(self)
    }

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
            refreshOverlay()
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
            refreshOverlay()
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
            refreshOverlay()
        case .eraser:
            break
        }
    }

    private func commitInk(on page: PDFPage) {
        // Tight bounds + path in the annotation's local space — the correct
        // shape for a saved `.ink` annotation (this is what other PDF readers
        // render). On-screen rendering is handled by the overlay, not this.
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
        records.append(StrokeRecord(page: page, annotation: annotation, bbox: box,
                                    points: pagePoints, color: inkColor, width: lineWidth))
    }

    private func eraseHit(_ p: CGPoint, on page: PDFPage) {
        let hits = records.filter { $0.page === page && $0.bbox.contains(p) }
        guard !hits.isEmpty else { return }
        for rec in hits { page.removeAnnotation(rec.annotation) }
        let removed = Set(hits.map { ObjectIdentifier($0.annotation) })
        records.removeAll { removed.contains(ObjectIdentifier($0.annotation)) }
        onEdited?()
        refreshOverlay()
    }

    /// Rebuild the overlay's view-space geometry from the page-space records +
    /// the live stroke, then repaint. Called on every draw event and on every
    /// scroll / zoom so the ink stays pinned to the page.
    @objc private func refreshOverlay() {
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
        ov.strokes = records.map { rec in
            StrokeOverlayView.Stroke(points: rec.points.map { convert($0, from: rec.page) },
                                     color: rec.color,
                                     width: max(1, rec.width * scaleFactor))
        }
        ov.live = overlayPoints.isEmpty
            ? nil
            : StrokeOverlayView.Stroke(points: overlayPoints, color: inkColor,
                                       width: max(1, lineWidth * scaleFactor))
        ov.needsDisplay = true
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

/// Transparent overlay that paints committed + in-progress ink in the
/// PDFView's own (view) coordinates. We render the ink ourselves because
/// macOS PDFKit no longer draws programmatic `.ink` annotations. Returns nil
/// from hitTest so all mouse events still reach the PDFView underneath.
final class StrokeOverlayView: NSView {
    struct Stroke {
        var points: [CGPoint]   // view coords
        var color: NSColor
        var width: CGFloat
    }
    /// Committed strokes, re-projected to view coords by the owner on each
    /// scroll / zoom.
    var strokes: [Stroke] = []
    /// In-progress stroke (nil when not drawing).
    var live: Stroke?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        for s in strokes { paint(s) }
        if let live { paint(live) }
    }

    private func paint(_ s: Stroke) {
        guard !s.points.isEmpty else { return }
        if s.points.count == 1 {
            let f = s.points[0]
            let r = CGRect(x: f.x - s.width / 2, y: f.y - s.width / 2, width: s.width, height: s.width)
            s.color.setFill()
            NSBezierPath(ovalIn: r).fill()
            return
        }
        let path = NSBezierPath()
        path.lineWidth = s.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: s.points[0])
        for p in s.points.dropFirst() { path.line(to: p) }
        s.color.setStroke()
        path.stroke()
    }
}
#endif
