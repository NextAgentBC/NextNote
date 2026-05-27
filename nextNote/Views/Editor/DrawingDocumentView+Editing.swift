import SwiftUI

// Ink editing + lasso selection on the focused page. Pure state mutation;
// no view code. Called from the gesture handlers in the main view.
extension DrawingDocumentView {

    // MARK: - Ink editing

    func clamp(_ p: CGPoint, height: CGFloat) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), pageWidth), y: min(max(p.y, 0), height))
    }

    func finalizeStroke(on i: Int) {
        if tool != .eraser, var s = current, pages.indices.contains(i) {
            if tool == .pen, snapShapes, let snapped = ShapeRecognizer.recognize(s.points) {
                s.points = snapped
            }
            pages[i].strokes.append(s)
            scheduleSave()
        }
        current = nil
    }

    func undo() {
        guard pages.indices.contains(focusedPage), !pages[focusedPage].strokes.isEmpty else { return }
        pages[focusedPage].strokes.removeLast()
        strokeSel = []; lassoPage = nil
        scheduleSave()
    }

    func clearPage() {
        guard pages.indices.contains(focusedPage), !pages[focusedPage].strokes.isEmpty else { return }
        pages[focusedPage].strokes.removeAll()
        strokeSel = []; lassoPage = nil
        scheduleSave()
    }

    func eraseAt(_ p: CGPoint, page i: Int) {
        guard pages.indices.contains(i) else { return }
        let radius: CGFloat = 14
        let before = pages[i].strokes.count
        pages[i].strokes.removeAll { stroke in
            stroke.points.contains { hypot($0.x - p.x, $0.y - p.y) <= max(radius, stroke.width) }
        }
        if pages[i].strokes.count != before { scheduleSave() }
    }

    func addPage() {
        current = nil
        pages.append(VMPage(strokes: [], background: nil, images: [], videos: []))
        focusedPage = pages.count - 1
        scheduleSave()
    }

    func deleteSelected() {
        if let sel = selectedImage, pages.indices.contains(sel.page),
           pages[sel.page].images.indices.contains(sel.index) {
            pages[sel.page].images.remove(at: sel.index)
            selectedImage = nil
            scheduleSave()
            return
        }
        if let sel = selectedVideo, pages.indices.contains(sel.page),
           pages[sel.page].videos.indices.contains(sel.index) {
            pages[sel.page].videos.remove(at: sel.index)
            selectedVideo = nil
            playingVideo = nil
            scheduleSave()
            return
        }
        if let pg = lassoPage, !strokeSel.isEmpty, pages.indices.contains(pg) {
            for idx in strokeSel.sorted(by: >) where pages[pg].strokes.indices.contains(idx) {
                pages[pg].strokes.remove(at: idx)
            }
            strokeSel = []; lassoPage = nil
            scheduleSave()
        }
    }

    // MARK: - Lasso selection (ink strokes)

    func lassoChanged(_ p: CGPoint, page i: Int) {
        if lassoMode == nil {
            // Drag starting inside an existing selection's box = move it.
            if lassoPage == i, !strokeSel.isEmpty,
               let box = selectionBox(page: i), box.insetBy(dx: -8, dy: -8).contains(p) {
                lassoMode = .move
                moveStart = p
                moveSnapshot = Dictionary(uniqueKeysWithValues: strokeSel.compactMap { idx in
                    pages[i].strokes.indices.contains(idx) ? (idx, pages[i].strokes[idx].points) : nil
                })
            } else {
                lassoMode = .draw
                lassoPage = i
                strokeSel = []
                lassoPoints = [p]
            }
            return
        }
        switch lassoMode! {
        case .draw:
            lassoPoints.append(p)
        case .move:
            guard let start = moveStart, let snap = moveSnapshot else { return }
            let dx = p.x - start.x, dy = p.y - start.y
            for (idx, orig) in snap where pages[i].strokes.indices.contains(idx) {
                pages[i].strokes[idx].points = orig.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            }
        }
    }

    func lassoEnded(page i: Int) {
        defer { lassoMode = nil; moveStart = nil; moveSnapshot = nil }
        switch lassoMode {
        case .move:
            scheduleSave()
        case .draw:
            let poly = lassoPoints
            lassoPoints = []
            guard poly.count >= 3, pages.indices.contains(i) else { strokeSel = []; lassoPage = nil; return }
            var sel = Set<Int>()
            for (idx, s) in pages[i].strokes.enumerated() where !s.points.isEmpty {
                let inside = s.points.filter { pointInPolygon($0, poly) }.count
                if inside * 2 >= s.points.count { sel.insert(idx) }   // majority inside
            }
            strokeSel = sel
            lassoPage = sel.isEmpty ? nil : i
        case .none:
            break
        }
    }

    func recolorSelection() {
        guard let pg = lassoPage, !strokeSel.isEmpty, pages.indices.contains(pg) else { return }
        for idx in strokeSel where pages[pg].strokes.indices.contains(idx) {
            pages[pg].strokes[idx].color = inkColor.color
        }
        scheduleSave()
    }

    func selectionBox(page i: Int) -> CGRect? {
        guard pages.indices.contains(i) else { return nil }
        var minX = CGFloat.greatestFiniteMagnitude, minY = minX
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = maxX
        var any = false
        for idx in strokeSel where pages[i].strokes.indices.contains(idx) {
            for p in pages[i].strokes[idx].points {
                any = true
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
        }
        return any ? CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY) : nil
    }

    func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y),
               p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
