import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// One pen stroke = ordered points + color + width. Stored on the model side
/// so the rendered PNG can be regenerated and the canvas can render via
/// SwiftUI Canvas (no PencilKit on macOS).
struct DrawStroke: Identifiable, Equatable {
    let id = UUID()
    var points: [CGPoint]
    var color: Color
    var width: CGFloat
}

/// Pure-SwiftUI drawing surface. Mouse / trackpad / touch input via
/// `DragGesture`. Strokes accumulate in `strokes`. Caller can also hold an
/// in-progress stroke separately so the live drag is visible without
/// constantly mutating the array.
struct DrawingCanvasView: View {
    @Binding var strokes: [DrawStroke]
    var color: Color
    var width: CGFloat

    @State private var current: DrawStroke?

    var body: some View {
        Canvas { ctx, _ in
            for s in strokes { draw(stroke: s, in: ctx) }
            if let s = current { draw(stroke: s, in: ctx) }
        }
        .background(Color.white)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if current == nil {
                        current = DrawStroke(points: [value.location], color: color, width: width)
                    } else {
                        current?.points.append(value.location)
                    }
                }
                .onEnded { _ in
                    if let s = current { strokes.append(s) }
                    current = nil
                }
        )
    }

    private func draw(stroke s: DrawStroke, in ctx: GraphicsContext) {
        guard s.points.count > 1 else {
            if let p = s.points.first {
                let rect = CGRect(x: p.x - s.width/2, y: p.y - s.width/2, width: s.width, height: s.width)
                ctx.fill(Path(ellipseIn: rect), with: .color(s.color))
            }
            return
        }
        var path = Path()
        path.move(to: s.points[0])
        for p in s.points.dropFirst() { path.addLine(to: p) }
        ctx.stroke(path, with: .color(s.color),
                   style: StrokeStyle(lineWidth: s.width, lineCap: .round, lineJoin: .round))
    }
}
