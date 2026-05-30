import SwiftUI

// Static rendering helpers for DrawingDocumentView — pure functions, no view
// state. Split out so the main view file stays focused on layout + gestures.
extension DrawingDocumentView {
    static func draw(stroke s: DrawStroke, in ctx: GraphicsContext) {
        guard s.points.count > 1 else {
            if let p = s.points.first {
                let rect = CGRect(x: p.x - s.width/2, y: p.y - s.width/2, width: s.width, height: s.width)
                ctx.fill(Path(ellipseIn: rect), with: .color(s.color))
            }
            return
        }
        ctx.stroke(smoothedPath(s.points), with: .color(s.color),
                   style: StrokeStyle(lineWidth: s.width, lineCap: .round, lineJoin: .round))
    }

    /// Accent halo behind a lasso-selected stroke.
    static func drawHalo(stroke s: DrawStroke, in ctx: GraphicsContext) {
        guard s.points.count > 1 else { return }
        ctx.stroke(smoothedPath(s.points), with: .color(.accentColor.opacity(0.35)),
                   style: StrokeStyle(lineWidth: s.width + 6, lineCap: .round, lineJoin: .round))
    }

    /// Quadratic-Bézier smoothing through segment midpoints — turns the raw
    /// polyline into smooth ink. Stored points are untouched (still re-editable
    /// / erasable / lasso-selectable); this is render-only. Wraps the CGPath
    /// builder below so on-screen ink and the PDF export share one geometry.
    static func smoothedPath(_ pts: [CGPoint]) -> Path { Path(cgSmoothedPath(pts)) }

    /// CGPath form of `smoothedPath` — the single source of stroke geometry,
    /// reused by `DrawingPDFRenderer` so exported ink matches the canvas exactly.
    static func cgSmoothedPath(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count == 2 { path.addLine(to: pts[1]); return path }
        path.addLine(to: midpoint(pts[0], pts[1]))
        for k in 1..<(pts.count - 1) {
            path.addQuadCurve(to: midpoint(pts[k], pts[k + 1]), control: pts[k])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}
