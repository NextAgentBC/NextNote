import SwiftUI

// Load / autosave for the `.nndraw` document — debounced JSON write through
// DrawingIO, plus initial in-memory cache hydration on first appearance.
extension DrawingDocumentView {
    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let doc = DrawingIO.load(url: fileURL) {
            pageWidth = CGFloat(doc.pageWidth)
            pageHeight = CGFloat(doc.pageHeight)
            pages = doc.pages.map { VMPage(strokes: $0.strokes.map { $0.drawStroke }, background: $0.background, images: $0.images, videos: $0.videos) }
            if pages.isEmpty { pages = [VMPage(strokes: [], background: nil, images: [], videos: [])] }
            #if os(macOS)
            for (idx, pg) in pages.enumerated() {
                if let bg = pg.background, let im = DrawingAssets.loadImage(bg, for: fileURL) { bgCache[idx] = im }
                for pimg in pg.images where imgCache[pimg.path] == nil {
                    if let im = DrawingAssets.loadImage(pimg.path, for: fileURL) { imgCache[pimg.path] = im }
                }
                for pv in pg.videos { loadThumb(pv.youtubeID) }
            }
            #endif
        }
        focusedPage = min(focusedPage, pages.count - 1)
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    func saveNow() {
        let doc = DrawingDoc(
            pageWidth: Double(pageWidth),
            pageHeight: Double(pageHeight),
            pages: pages.map {
                DrawPage(strokes: $0.strokes.map { CodableStroke(from: $0) },
                         background: $0.background, images: $0.images, videos: $0.videos)
            }
        )
        do {
            try DrawingIO.save(url: fileURL, doc: doc)
            saveError = nil
        } catch {
            saveError = "Save failed: \(error.localizedDescription)"
        }
    }
}
