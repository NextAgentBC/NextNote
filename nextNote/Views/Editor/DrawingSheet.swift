import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Modal sheet for sketching a drawing. On Save, renders the strokes to a
/// PNG at `<noteDir>/<noteBase>.assets/drawing-<timestamp>.png` and calls
/// `onSave` with the relative markdown path.
struct DrawingSheet: View {
    let noteURL: URL?
    let noteBaseName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var strokes: [DrawStroke] = []
    @State private var inkColor: InkColor = .black
    @State private var width: CGFloat = 3
    @State private var canvasSize: CGSize = .zero
    @State private var saveError: String?

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()

    enum InkColor: String, CaseIterable, Identifiable {
        case black, blue, red, green
        var id: String { rawValue }
        var color: Color {
            switch self {
            case .black: return .black
            case .blue:  return .blue
            case .red:   return .red
            case .green: return .green
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Drawing").font(.headline)

                Spacer()

                Picker("Color", selection: $inkColor) {
                    ForEach(InkColor.allCases) { c in
                        Text(c.rawValue.capitalized).tag(c)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                HStack(spacing: 4) {
                    Text("Width")
                    Slider(value: $width, in: 1...12).frame(width: 100)
                }

                Button("Undo") {
                    if !strokes.isEmpty { strokes.removeLast() }
                }
                .disabled(strokes.isEmpty)

                Button("Clear") { strokes.removeAll() }
                    .disabled(strokes.isEmpty)

                Button("Cancel", role: .cancel) { onCancel() }

                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(strokes.isEmpty)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))

            Divider()

            GeometryReader { geo in
                DrawingCanvasView(strokes: $strokes, color: inkColor.color, width: width)
                    .onAppear { canvasSize = geo.size }
                    .onChange(of: geo.size) { _, s in canvasSize = s }
            }

            if let err = saveError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
            }
        }
        .frame(minWidth: 400, idealWidth: 900, minHeight: 300, idealHeight: 640)
    }

    private func save() {
        guard let noteURL else {
            saveError = "Save the note to disk first (vault mode)."
            return
        }
        guard !strokes.isEmpty, canvasSize.width > 0, canvasSize.height > 0 else { return }

        guard let png = renderPNG(size: canvasSize) else {
            saveError = "Failed to render drawing"; return
        }

        let noteDir = noteURL.deletingLastPathComponent()
        let assetsDirName = "\(noteBaseName).assets"
        let assetsDir = noteDir.appendingPathComponent(assetsDirName, isDirectory: true)

        let stamp = DrawingSheet.timestampFormatter.string(from: Date())
        let filename = "drawing-\(stamp).png"
        let dest = assetsDir.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
            try png.write(to: dest, options: .atomic)
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
            return
        }

        onSave("\(assetsDirName)/\(filename)")
    }

    @MainActor
    private func renderPNG(size: CGSize) -> Data? {
        let view = ZStack {
            Color.white
            Canvas { ctx, _ in
                for s in strokes { Self.draw(stroke: s, in: ctx) }
            }
        }
        .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        #if os(macOS)
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #else
        return renderer.uiImage?.pngData()
        #endif
    }

    static func draw(stroke s: DrawStroke, in ctx: GraphicsContext) {
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

#if os(macOS)
/// Hosts `DrawingSheet` in a standalone, freely resizable NSWindow instead of
/// a fixed-size SwiftUI `.sheet`. Singleton — re-opening with the canvas
/// already up just brings the window forward.
@MainActor
final class DrawingWindowController {
    static let shared = DrawingWindowController()
    private var controller: NSWindowController?

    func show(noteURL: URL?, baseName: String, onSave: @escaping (String) -> Void) {
        if let c = controller, let w = c.window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = DrawingSheet(
            noteURL: noteURL,
            noteBaseName: baseName,
            onSave: { [weak self] rel in
                onSave(rel)
                self?.close()
            },
            onCancel: { [weak self] in self?.close() }
        )
        let host = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Drawing — \(baseName)"
        window.contentViewController = host
        window.center()
        window.isReleasedWhenClosed = false

        let c = NSWindowController(window: window)
        controller = c
        c.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        controller?.close()
        controller = nil
    }
}
#endif
