import SwiftUI
import CoreGraphics
#if os(macOS)
import AppKit
#endif

/// On-disk, re-editable persistence model for a `.nndraw` drawing note.
/// Stored as JSON in the Notes vault alongside `.md` files. Keeps the raw
/// stroke geometry so the drawing can be reopened and edited (unlike the
/// flattened-PNG path used when embedding a sketch into markdown).
struct DrawingDoc: Codable {
    /// US Letter @ 72 dpi (points). Default page size; maps 1:1 to a PDF page.
    static let letterWidth: Double = 612    // 8.5 in
    static let letterHeight: Double = 792   // 11 in

    var version: Int
    var pageWidth: Double
    var pageHeight: Double
    var pages: [DrawPage]

    init(version: Int = 3,
         pageWidth: Double = DrawingDoc.letterWidth,
         pageHeight: Double = DrawingDoc.letterHeight,
         pages: [DrawPage] = [DrawPage()]) {
        self.version = version
        self.pageWidth = pageWidth
        self.pageHeight = pageHeight
        self.pages = pages.isEmpty ? [DrawPage()] : pages
    }

    private enum CodingKeys: String, CodingKey {
        case version, pageWidth, pageHeight, pages, strokes
    }

    // Tolerant decode across formats:
    //   v3 = pages:[DrawPage]  •  v2 = pages:[[CodableStroke]]  •  v1 = strokes:[CodableStroke]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        pageWidth = (try? c.decode(Double.self, forKey: .pageWidth)) ?? DrawingDoc.letterWidth
        pageHeight = (try? c.decode(Double.self, forKey: .pageHeight)) ?? DrawingDoc.letterHeight
        if let p3 = try? c.decode([DrawPage].self, forKey: .pages) {
            pages = p3
        } else if let p2 = try? c.decode([[CodableStroke]].self, forKey: .pages) {
            pages = p2.map { DrawPage(strokes: $0) }
        } else if let s1 = try? c.decode([CodableStroke].self, forKey: .strokes) {
            pages = [DrawPage(strokes: s1)]
        } else {
            pages = [DrawPage()]
        }
        if pages.isEmpty { pages = [DrawPage()] }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(pageWidth, forKey: .pageWidth)
        try c.encode(pageHeight, forKey: .pageHeight)
        try c.encode(pages, forKey: .pages)
    }
}

/// One page: ink strokes plus an optional full-page background image — an
/// imported PDF-page render or a pasted screenshot — drawn aspect-fit behind
/// the strokes. `background` is a path relative to the `.nndraw` file.
struct DrawPage: Codable {
    var strokes: [CodableStroke]
    /// Full-page background (imported PDF page / dropped image), aspect-fit.
    var background: String?
    /// Free-floating, movable + resizable images (pasted screenshots) placed
    /// in page coordinates, drawn under the ink.
    var images: [PlacedImage]
    /// Placed YouTube video cards (thumbnail + click-to-play), movable +
    /// resizable in page coordinates, drawn over the ink.
    var videos: [PlacedVideo]

    init(strokes: [CodableStroke] = [], background: String? = nil,
         images: [PlacedImage] = [], videos: [PlacedVideo] = []) {
        self.strokes = strokes
        self.background = background
        self.images = images
        self.videos = videos
    }

    private enum CodingKeys: String, CodingKey { case strokes, background, images, videos }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strokes = (try? c.decode([CodableStroke].self, forKey: .strokes)) ?? []
        background = try? c.decode(String.self, forKey: .background)
        images = (try? c.decode([PlacedImage].self, forKey: .images)) ?? []
        videos = (try? c.decode([PlacedVideo].self, forKey: .videos)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(strokes, forKey: .strokes)
        try c.encodeIfPresent(background, forKey: .background)
        try c.encode(images, forKey: .images)
        try c.encode(videos, forKey: .videos)
    }
}

/// A placed image on a page: asset path + frame in page coordinates.
struct PlacedImage: Codable {
    var path: String
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

/// A placed YouTube video card: the 11-char video id + frame in page
/// coordinates. Rendered as a thumbnail with a play button; clicking swaps
/// it for an inline WKWebView player. Only the id is stored, so the doc stays
/// small and portable (the thumbnail is fetched on demand).
struct PlacedVideo: Codable {
    var youtubeID: String
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

/// Codable mirror of `DrawStroke` (whose `Color` isn't directly Codable).
/// Colour is stored as sRGB components so highlighter alpha round-trips.
struct CodableStroke: Codable {
    var points: [CGPoint]   // CGPoint is Codable in Foundation
    var r: Double
    var g: Double
    var b: Double
    var a: Double
    var width: Double

    init(from s: DrawStroke) {
        self.points = s.points
        let (r, g, b, a) = s.color.rgbaComponents
        self.r = r; self.g = g; self.b = b; self.a = a
        self.width = Double(s.width)
    }

    var drawStroke: DrawStroke {
        DrawStroke(
            points: points,
            color: Color(.sRGB, red: r, green: g, blue: b, opacity: a),
            width: CGFloat(width)
        )
    }
}

extension Color {
    /// Resolve to sRGB (r,g,b,a) components in 0...1. Falls back gracefully if
    /// the colour can't be converted to the sRGB space.
    var rgbaComponents: (Double, Double, Double, Double) {
        #if os(macOS)
        let base = NSColor(self)
        let ns = base.usingColorSpace(.sRGB) ?? base.usingColorSpace(.deviceRGB)
        guard let c = ns else { return (0, 0, 0, 1) }
        return (Double(c.redComponent), Double(c.greenComponent),
                Double(c.blueComponent), Double(c.alphaComponent))
        #else
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #endif
    }
}
