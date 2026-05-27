import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

// Adding media to the drawing canvas — paste a screenshot, import a PDF as
// page backgrounds, embed a YouTube video, or render the parent markdown
// note as a background. Toolbar buttons in the main view fan out here.
extension DrawingDocumentView {
    #if os(macOS)
    func paste() {
        guard let img = DrawingAssets.clipboardImage() else { saveError = "No image in the clipboard"; return }
        guard let rel = DrawingAssets.savePNG(img, for: fileURL, prefix: "paste") else {
            saveError = "Couldn't save pasted image"; return
        }
        guard pages.indices.contains(focusedPage) else { return }
        // Place on the CURRENT page, centered, aspect-fit to ~60% width.
        let nat = img.size
        let maxW = pageWidth * 0.6
        let scale = (nat.width > maxW && nat.width > 0) ? maxW / nat.width : 1
        let w = max(60, nat.width * scale)
        let h = max(60, nat.height * scale)
        let x = (pageWidth - w) / 2
        let y = (pageHeight - h) / 2
        imgCache[rel] = img
        pages[focusedPage].images.append(PlacedImage(path: rel, x: x, y: y, w: w, h: h))
        tool = .select
        selectedImage = ImgSel(page: focusedPage, index: pages[focusedPage].images.count - 1)
        saveError = nil
        scheduleSave()
    }

    func importPDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importing = true
        Task {
            let images = await Task.detached(priority: .userInitiated) { DrawingAssets.renderPDF(url) }.value
            await MainActor.run {
                let firstNew = pages.count
                for img in images {
                    if let rel = DrawingAssets.savePNG(img, for: fileURL, prefix: "pdf") {
                        pages.append(VMPage(strokes: [], background: rel, images: [], videos: []))
                        bgCache[pages.count - 1] = img
                    }
                }
                if !images.isEmpty { focusedPage = firstNew } else { saveError = "Couldn't read that PDF" }
                importing = false
                scheduleSave()
            }
        }
    }

    /// Render the associated markdown note to a PDF (same pipeline as the
    /// preview), rasterize its pages, and set them as page backgrounds to
    /// annotate over. Overwrites backgrounds but keeps existing ink per page.
    func syncFromMarkdown() {
        guard let md = markdownSource,
              !md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            saveError = "Note has no text to render"; return
        }
        importing = true
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("nndraw-mdbg-\(UUID().uuidString).pdf")
        PDFExporter.export(markdown: md, baseURL: markdownBaseURL, destination: tmp) { result in
            Task { @MainActor in
                importing = false
                switch result {
                case .success(let url):
                    let images = DrawingAssets.renderPDF(url, maxPages: 60)
                    try? FileManager.default.removeItem(at: url)
                    guard !images.isEmpty else { saveError = "Couldn't render the note"; return }
                    for (i, img) in images.enumerated() {
                        if i >= pages.count {
                            pages.append(VMPage(strokes: [], background: nil, images: [], videos: []))
                        }
                        if let rel = DrawingAssets.savePNG(img, for: fileURL, prefix: "mdbg") {
                            pages[i].background = rel
                            bgCache[i] = img
                        }
                    }
                    saveError = nil
                    scheduleSave()
                case .failure(let e):
                    saveError = "Render failed: \(e.localizedDescription)"
                }
            }
        }
    }

    func embedYouTube() {
        let pb = NSPasteboard.general.string(forType: .string) ?? ""
        let prefill = MarkdownEmbeds.extractYouTubeID(from: pb) != nil ? pb : ""
        let alert = NSAlert()
        alert.messageText = "Embed YouTube video"
        alert.informativeText = "Paste a YouTube link (youtube.com/watch?v=… or youtu.be/…)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://youtu.be/…"
        field.stringValue = prefill
        alert.accessoryView = field
        alert.addButton(withTitle: "Embed")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let id = MarkdownEmbeds.extractYouTubeID(from: field.stringValue) else {
            saveError = "That doesn't look like a YouTube link"; return
        }
        guard pages.indices.contains(focusedPage) else { return }
        let w = pageWidth * 0.6
        let h = w * 9.0 / 16.0
        let x = (pageWidth - w) / 2
        let y = (pageHeight - h) / 2
        pages[focusedPage].videos.append(PlacedVideo(youtubeID: id, x: x, y: y, w: w, h: h))
        loadThumb(id)
        tool = .select
        selectedImage = nil
        selectedVideo = VidSel(page: focusedPage, index: pages[focusedPage].videos.count - 1)
        saveError = nil
        scheduleSave()
    }

    func loadThumb(_ id: String) {
        guard thumbCache[id] == nil,
              let url = URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg") else { return }
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let img = NSImage(data: data) {
                await MainActor.run { thumbCache[id] = img }
            }
        }
    }
    #else
    func paste() {}
    func importPDF() {}
    func syncFromMarkdown() {}
    func embedYouTube() {}
    func loadThumb(_ id: String) {}
    #endif
}
