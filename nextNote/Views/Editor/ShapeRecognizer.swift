import CoreGraphics
import Foundation

/// Lightweight freehand shape recognizer. Given a raw stroke's points, returns
/// idealized points for a clean straight line / axis-aligned rectangle /
/// ellipse / triangle when there's a confident match, else `nil` (keep raw).
///
/// Deliberately conservative: it only snaps when the fit is clearly good, so it
/// helps tidy diagrams without fighting genuine freehand sketching. The result
/// is still just a list of points → stays a normal editable/erasable stroke.
enum ShapeRecognizer {
    static func recognize(_ pts: [CGPoint]) -> [CGPoint]? {
        guard pts.count >= 6 else { return nil }
        let box = bbox(pts)
        let diag = hypot(box.width, box.height)
        guard diag > 28 else { return nil }            // too small to bother

        let closed = dist(pts.first!, pts.last!) < diag * 0.28

        if !closed {
            // Straight line: low perpendicular deviation from the chord.
            if maxPerpDev(pts, a: pts.first!, b: pts.last!) < diag * 0.07 {
                return [pts.first!, pts.last!]
            }
            return nil                                  // open curve / arrow — leave raw
        }

        // Closed shape. Compare rectangle-fit vs ellipse-fit, and corner count.
        let rErr = rectError(pts, box: box)
        let eErr = ellipseError(pts, box: box)
        let corners = dedupeClosed(rdp(pts, epsilon: diag * 0.07), tol: diag * 0.12)

        // A very clean round/rectangular loop wins outright (guards against a
        // tidy circle being mis-read as a triangle by the corner pass).
        if min(rErr, eErr) < 0.11 {
            return rErr <= eErr ? rectPoints(box) : ellipsePoints(box)
        }
        if corners.count == 3 {
            return closePath(corners)                   // triangle (keeps orientation)
        }
        if min(rErr, eErr) < 0.16 {
            return rErr <= eErr ? rectPoints(box) : ellipsePoints(box)
        }
        return nil                                      // not a clean shape — keep raw
    }

    // MARK: - Geometry helpers

    private static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private static func bbox(_ pts: [CGPoint]) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude, minY = minX
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = maxX
        for p in pts {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func maxPerpDev(_ pts: [CGPoint], a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy); guard len > 0 else { return 0 }
        var m: CGFloat = 0
        for p in pts { m = max(m, abs(dy * (p.x - a.x) - dx * (p.y - a.y)) / len) }
        return m
    }

    /// Ramer–Douglas–Peucker polyline simplification.
    private static func rdp(_ pts: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        let a = pts.first!, b = pts.last!
        let dx = b.x - a.x, dy = b.y - a.y, len = max(hypot(dx, dy), 0.0001)
        var dmax: CGFloat = 0, index = 0
        for i in 1..<(pts.count - 1) {
            let p = pts[i]
            let d = abs(dy * (p.x - a.x) - dx * (p.y - a.y)) / len
            if d > dmax { dmax = d; index = i }
        }
        if dmax > epsilon {
            let left = rdp(Array(pts[0...index]), epsilon: epsilon)
            let right = rdp(Array(pts[index...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        }
        return [a, b]
    }

    private static func dedupeClosed(_ pts: [CGPoint], tol: CGFloat) -> [CGPoint] {
        var out: [CGPoint] = []
        for p in pts {
            if let last = out.last, dist(last, p) < tol { continue }
            out.append(p)
        }
        if out.count > 1, dist(out.first!, out.last!) < tol { out.removeLast() }
        return out
    }

    private static func closePath(_ corners: [CGPoint]) -> [CGPoint] {
        guard let first = corners.first else { return corners }
        return corners + [first]
    }

    private static func rectPoints(_ b: CGRect) -> [CGPoint] {
        [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
         CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY),
         CGPoint(x: b.minX, y: b.minY)]
    }

    private static func ellipsePoints(_ b: CGRect) -> [CGPoint] {
        let cx = b.midX, cy = b.midY, rx = b.width / 2, ry = b.height / 2
        let n = 48
        return (0...n).map { k in
            let t = Double(k) / Double(n) * 2 * Double.pi
            return CGPoint(x: cx + rx * CGFloat(cos(t)), y: cy + ry * CGFloat(sin(t)))
        }
    }

    /// Mean normalized distance of points to the nearest axis-aligned bbox edge.
    private static func rectError(_ pts: [CGPoint], box b: CGRect) -> CGFloat {
        let norm = max(b.width, b.height) / 2
        guard norm > 0 else { return .greatestFiniteMagnitude }
        var sum: CGFloat = 0
        for p in pts {
            let dxEdge = min(abs(p.x - b.minX), abs(p.x - b.maxX))
            let dyEdge = min(abs(p.y - b.minY), abs(p.y - b.maxY))
            sum += min(dxEdge, dyEdge)
        }
        return (sum / CGFloat(pts.count)) / norm
    }

    /// Mean |radius − 1| of points vs the bbox-inscribed ellipse (0 == on it).
    private static func ellipseError(_ pts: [CGPoint], box b: CGRect) -> CGFloat {
        let rx = b.width / 2, ry = b.height / 2
        guard rx > 1, ry > 1 else { return .greatestFiniteMagnitude }
        let cx = b.midX, cy = b.midY
        var sum: CGFloat = 0
        for p in pts {
            let nx = (p.x - cx) / rx, ny = (p.y - cy) / ry
            sum += abs(sqrt(nx * nx + ny * ny) - 1)
        }
        return sum / CGFloat(pts.count)
    }
}
