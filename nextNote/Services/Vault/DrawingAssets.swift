import Foundation
#if os(macOS)
import AppKit
import PDFKit

/// Asset storage + rendering helpers for `.nndraw` drawing notes.
/// Images live in a hidden, co-located folder `.<filename>.assets/` so the
/// sidebar scanner (which skips dot-files) never surfaces them.
enum DrawingAssets {
    static func assetsDirName(for fileURL: URL) -> String {
        "." + fileURL.lastPathComponent + ".assets"
    }

    static func assetsDir(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent(assetsDirName(for: fileURL), isDirectory: true)
    }

    static func resolve(_ relativePath: String, for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(relativePath)
    }

    static func loadImage(_ relativePath: String, for fileURL: URL) -> NSImage? {
        NSImage(contentsOf: resolve(relativePath, for: fileURL))
    }

    /// Save an image as PNG into the note's assets dir. Returns a path relative
    /// to the `.nndraw` file (e.g. ".Foo.nndraw.assets/paste-123.png").
    @discardableResult
    static func savePNG(_ image: NSImage, for fileURL: URL, prefix: String) -> String? {
        let dir = assetsDir(for: fileURL)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let png = pngData(image) else { return nil }
        let name = "\(prefix)-\(Int(Date().timeIntervalSince1970 * 1000))-\(Int.random(in: 0...9999)).png"
        let url = dir.appendingPathComponent(name)
        do {
            try png.write(to: url, options: .atomic)
            return assetsDirName(for: fileURL) + "/" + name
        } catch {
            return nil
        }
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Render up to `maxPages` PDF pages to images for use as page backgrounds.
    static func renderPDF(_ pdfURL: URL, maxPages: Int = 60, scale: CGFloat = 2.0) -> [NSImage] {
        guard let doc = PDFDocument(url: pdfURL) else { return [] }
        var out: [NSImage] = []
        for i in 0..<min(doc.pageCount, maxPages) {
            guard let page = doc.page(at: i) else { continue }
            let b = page.bounds(for: .mediaBox)
            let size = NSSize(width: max(b.width, 1) * scale, height: max(b.height, 1) * scale)
            out.append(page.thumbnail(of: size, for: .mediaBox))
        }
        return out
    }

    static func clipboardImage() -> NSImage? {
        let pb = NSPasteboard.general
        if let imgs = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let first = imgs.first {
            return first
        }
        return nil
    }
}
#endif
