import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// Full-tab editor for a `.nndraw` drawing note. Letter-size "paper" pages in a
/// continuous vertical scroll, with zoom (incl. Fit Width) and multi-page.
/// Each page can carry a full-page background (imported PDF page) and free
/// placed images (pasted screenshots — movable/resizable in Select mode),
/// both drawn under the ink. Press-drag draws; holding ⌥ + moving also draws.
struct DrawingDocumentView: View {
    let fileURL: URL
    /// When this drawing is the "Draw" layer of a markdown note, its rendered
    /// text can be loaded as the page background(s) to annotate over.
    var markdownSource: String? = nil
    var markdownBaseURL: URL? = nil

    enum Tool: String, CaseIterable, Identifiable {
        case select, pen, highlighter, eraser
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .select:      return "cursorarrow"
            case .pen:         return "pencil.tip"
            case .highlighter: return "highlighter"
            case .eraser:      return "eraser"
            }
        }
        var isDrawing: Bool { self == .pen || self == .highlighter || self == .eraser }
    }

    enum InkColor: String, CaseIterable, Identifiable {
        case black, blue, red, green, orange
        var id: String { rawValue }
        var color: Color {
            switch self {
            case .black:  return .black
            case .blue:   return .blue
            case .red:    return .red
            case .green:  return .green
            case .orange: return .orange
            }
        }
    }

    private struct VMPage {
        var strokes: [DrawStroke]
        var background: String?
        var images: [PlacedImage]
        var videos: [PlacedVideo]
    }
    private struct ImgSel: Equatable { var page: Int; var index: Int }
    private struct VidSel: Equatable { var page: Int; var index: Int }

    private static let minZoom: CGFloat = 0.25
    private static let maxZoom: CGFloat = 4.0

    @State private var pages: [VMPage] = [VMPage(strokes: [], background: nil, images: [], videos: [])]
    @State private var bgCache: [Int: NSImage] = [:]
    @State private var imgCache: [String: NSImage] = [:]
    @State private var current: DrawStroke?
    @State private var focusedPage: Int = 0
    @State private var pageWidth: CGFloat = CGFloat(DrawingDoc.letterWidth)
    @State private var pageHeight: CGFloat = CGFloat(DrawingDoc.letterHeight)
    @State private var tool: Tool = .pen
    @State private var inkColor: InkColor = .black
    @State private var penWidth: CGFloat = 3
    @State private var highlighterWidth: CGFloat = 16
    @State private var zoom: CGFloat = 1.0
    @State private var containerWidth: CGFloat = 0
    @State private var scrollTopToken = 0
    @State private var didInitialFit = false
    @State private var importing = false
    @State private var loaded = false
    @State private var saveError: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var optionDown = false
    @State private var isPressing = false
    @State private var selectedImage: ImgSel?
    @State private var imgBaseline: CGPoint?
    @State private var selectedVideo: VidSel?
    @State private var vidBaseline: CGPoint?
    @State private var playingVideo: VidSel?
    @State private var thumbCache: [String: NSImage] = [:]
    #if os(macOS)
    @State private var flagsMonitor: Any?
    #endif

    private var activeColor: Color {
        tool == .highlighter ? inkColor.color.opacity(0.3) : inkColor.color
    }
    private var activeWidth: CGFloat {
        tool == .highlighter ? highlighterWidth : penWidth
    }
    private var focusedEmpty: Bool {
        !pages.indices.contains(focusedPage) || pages[focusedPage].strokes.isEmpty
    }
    /// No ink, no backgrounds, no placed images anywhere — a pristine canvas.
    private var isDrawingEmpty: Bool {
        pages.allSatisfy { $0.strokes.isEmpty && $0.background == nil && $0.images.isEmpty && $0.videos.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            pagesScroll
            Divider()
            bottomBar
            if let saveError {
                Text(saveError).font(.caption).foregroundStyle(.red).padding(6)
            }
        }
        .onChange(of: tool) { _, t in if t != .select { selectedImage = nil; selectedVideo = nil; playingVideo = nil } }
        .onDeleteCommand { deleteSelected() }
        .onAppear {
            loadIfNeeded()
            #if os(macOS)
            installModifierMonitor()
            // First time you draw on a markdown note: drop its rendered text in
            // as the background so you annotate over the formatted note.
            if markdownSource != nil, isDrawingEmpty { syncFromMarkdown() }
            #endif
        }
        .onDisappear {
            saveNow()
            #if os(macOS)
            removeModifierMonitor()
            #endif
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            Picker("Tool", selection: $tool) {
                ForEach(Tool.allCases) { t in Image(systemName: t.icon).tag(t) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 168).help("Tool")

            Picker("Color", selection: $inkColor) {
                ForEach(InkColor.allCases) { c in Text(c.rawValue.capitalized).tag(c) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 280)
            .disabled(!tool.isDrawing || tool == .eraser)

            HStack(spacing: 4) {
                Image(systemName: "lineweight")
                Slider(value: tool == .highlighter ? $highlighterWidth : $penWidth, in: 1...40)
                    .frame(width: 100)
            }
            .disabled(!tool.isDrawing || tool == .eraser)

            Spacer()

            Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(focusedEmpty).help("Undo (current page)")
            Button(role: .destructive) { clearPage() } label: { Image(systemName: "trash") }
                .disabled(focusedEmpty).help("Clear current page")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial)
    }

    // MARK: - Pages (continuous vertical scroll)

    private var pagesScroll: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    VStack(spacing: 24) {
                        Color.clear.frame(width: 1, height: 1).id("pagesTop")
                        ForEach(pages.indices, id: \.self) { i in
                            VStack(spacing: 4) {
                                Text("Page \(i + 1)")
                                    .font(.caption2).foregroundStyle(.secondary)
                                pageView(i)
                            }
                        }
                    }
                    .padding(.vertical, 28)
                    .padding(.horizontal, max(28, (geo.size.width - pageWidth * zoom) / 2))
                }
                .background(Color(white: 0.90))
                .onChange(of: scrollTopToken) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("pagesTop", anchor: .top) }
                }
            }
            .onAppear { containerWidth = geo.size.width; applyInitialFitIfNeeded() }
            .onChange(of: geo.size.width) { _, w in containerWidth = w; applyInitialFitIfNeeded() }
        }
    }

    private func pageView(_ i: Int) -> some View {
        let h = pageRenderHeight(i)
        return ZStack {
            if let bg = bgCache[i] {
                // Fit width: the page height already matches the image aspect,
                // so a plain resize fills the page edge-to-edge, no distortion.
                Image(nsImage: bg)
                    .resizable().interpolation(.medium)
                    .frame(width: pageWidth * zoom, height: h * zoom)
                    .allowsHitTesting(false)
            }
            if pages.indices.contains(i) {
                ForEach(pages[i].images.indices, id: \.self) { j in
                    placedImageView(page: i, index: j)
                }
            }
            if pages.indices.contains(i) {
                ForEach(pages[i].videos.indices, id: \.self) { j in
                    placedVideoView(page: i, index: j)
                }
            }
            Canvas { context, _ in
                var ctx = context
                ctx.scaleBy(x: zoom, y: zoom)
                if pages.indices.contains(i) {
                    for s in pages[i].strokes { Self.draw(stroke: s, in: ctx) }
                }
                if i == focusedPage, let s = current { Self.draw(stroke: s, in: ctx) }
            }
            .frame(width: pageWidth * zoom, height: h * zoom)
            .allowsHitTesting(tool != .select)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let loc):
                    guard optionDown, !isPressing else { return }
                    focusedPage = i
                    let p = clamp(CGPoint(x: loc.x / zoom, y: loc.y / zoom), height: h)
                    if tool == .eraser { eraseAt(p, page: i); return }
                    if current == nil {
                        current = DrawStroke(points: [p], color: activeColor, width: activeWidth)
                    } else {
                        current?.points.append(p)
                    }
                case .ended:
                    if focusedPage == i, !isPressing { finalizeStroke(on: i) }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isPressing = true
                        focusedPage = i
                        let p = clamp(CGPoint(x: value.location.x / zoom, y: value.location.y / zoom), height: h)
                        if tool == .eraser { eraseAt(p, page: i); return }
                        if current == nil {
                            current = DrawStroke(points: [p], color: activeColor, width: activeWidth)
                        } else {
                            current?.points.append(p)
                        }
                    }
                    .onEnded { _ in finalizeStroke(on: i); isPressing = false }
            )
        }
        .frame(width: pageWidth * zoom, height: h * zoom)
        .background(Color.white)
        .overlay(Rectangle().stroke(
            optionDown ? Color.accentColor.opacity(0.85) : Color.gray.opacity(0.35),
            lineWidth: optionDown ? 2 : 1))
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
    }

    /// A page with a background fills the width and grows as tall as the
    /// background needs (so long notes / portrait PDFs aren't squished into a
    /// narrow strip). Blank pages stay Letter-tall.
    private func pageRenderHeight(_ i: Int) -> CGFloat {
        if let img = bgCache[i], img.size.width > 0 {
            return pageWidth * (img.size.height / img.size.width)
        }
        return pageHeight
    }

    private func placedImageView(page i: Int, index j: Int) -> some View {
        let img = pages[i].images[j]
        let selected = (selectedImage == ImgSel(page: i, index: j)) && tool == .select
        return Group {
            if let ns = imgCache[img.path] {
                Image(nsImage: ns).resizable().interpolation(.medium)
            } else {
                Color.gray.opacity(0.15)
            }
        }
        .frame(width: img.w * zoom, height: img.h * zoom)
        .overlay { if selected { Rectangle().stroke(Color.accentColor, lineWidth: 2) } }
        .overlay(alignment: .topLeading) {
            if selected {
                Button(role: .destructive) { deleteSelected() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain).offset(x: -7, y: -7).help("Delete image")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if selected {
                Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .background(Circle().fill(.white))
                    .offset(x: 7, y: 7)
                    .highPriorityGesture(
                        DragGesture()
                            .onChanged { v in
                                if imgBaseline == nil { imgBaseline = CGPoint(x: img.w, y: img.h) }
                                guard let base = imgBaseline, pages.indices.contains(i),
                                      pages[i].images.indices.contains(j) else { return }
                                let newW = max(30, base.x + v.translation.width / zoom)
                                let ratio = base.y / max(base.x, 1)
                                pages[i].images[j].w = newW
                                pages[i].images[j].h = max(30, newW * ratio)
                            }
                            .onEnded { _ in imgBaseline = nil; scheduleSave() }
                    )
            }
        }
        .position(x: (img.x + img.w / 2) * zoom, y: (img.y + img.h / 2) * zoom)
        .allowsHitTesting(tool == .select)
        .onTapGesture { if tool == .select { selectedVideo = nil; selectedImage = ImgSel(page: i, index: j) } }
        .gesture(
            DragGesture()
                .onChanged { v in
                    selectedImage = ImgSel(page: i, index: j)
                    if imgBaseline == nil { imgBaseline = CGPoint(x: img.x, y: img.y) }
                    guard let base = imgBaseline, pages.indices.contains(i),
                          pages[i].images.indices.contains(j) else { return }
                    pages[i].images[j].x = base.x + v.translation.width / zoom
                    pages[i].images[j].y = base.y + v.translation.height / zoom
                }
                .onEnded { _ in imgBaseline = nil; scheduleSave() }
        )
    }

    private func placedVideoView(page i: Int, index j: Int) -> some View {
        let vid = pages[i].videos[j]
        let sel = VidSel(page: i, index: j)
        let selected = (selectedVideo == sel) && tool == .select
        let playing = (playingVideo == sel)
        return ZStack {
            if playing {
                YouTubeEmbedWebView(youtubeID: vid.youtubeID)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Group {
                    if let ns = thumbCache[vid.youtubeID] {
                        Image(nsImage: ns).resizable().interpolation(.medium)
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.black.opacity(0.85)
                    }
                }
                .frame(width: vid.w * zoom, height: vid.h * zoom)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    Button {
                        guard tool == .select else { return }
                        selectedImage = nil; selectedVideo = sel; playingVideo = sel
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.92))
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: vid.w * zoom, height: vid.h * zoom)
        .overlay { if selected { RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2) } }
        .overlay(alignment: .topLeading) {
            if selected && !playing {
                Button(role: .destructive) { deleteSelected() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain).offset(x: -7, y: -7).help("Delete video")
            }
        }
        .overlay(alignment: .topTrailing) {
            if playing {
                Button { playingVideo = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain).padding(6)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if selected && !playing {
                Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .background(Circle().fill(.white))
                    .offset(x: 7, y: 7)
                    .highPriorityGesture(
                        DragGesture()
                            .onChanged { v in
                                if vidBaseline == nil { vidBaseline = CGPoint(x: vid.w, y: vid.h) }
                                guard let base = vidBaseline, pages.indices.contains(i),
                                      pages[i].videos.indices.contains(j) else { return }
                                let newW = max(120, base.x + v.translation.width / zoom)
                                pages[i].videos[j].w = newW
                                pages[i].videos[j].h = max(68, newW * 9.0 / 16.0)
                            }
                            .onEnded { _ in vidBaseline = nil; scheduleSave() }
                    )
            }
        }
        .position(x: (vid.x + vid.w / 2) * zoom, y: (vid.y + vid.h / 2) * zoom)
        .allowsHitTesting(tool == .select)
        .gesture(TapGesture().onEnded {
            if tool == .select { selectedImage = nil; selectedVideo = sel }
        }, including: playing ? .subviews : .all)
        .gesture(
            DragGesture()
                .onChanged { v in
                    selectedImage = nil; selectedVideo = sel
                    if vidBaseline == nil { vidBaseline = CGPoint(x: vid.x, y: vid.y) }
                    guard let base = vidBaseline, pages.indices.contains(i),
                          pages[i].videos.indices.contains(j) else { return }
                    pages[i].videos[j].x = base.x + v.translation.width / zoom
                    pages[i].videos[j].y = base.y + v.translation.height / zoom
                }
                .onEnded { _ in vidBaseline = nil; scheduleSave() },
            including: playing ? .subviews : .all
        )
    }

    // MARK: - Bottom bar

    private var hintText: String {
        if tool == .select { return "Select: drag to move · corner to resize" }
        if optionDown { return "Drawing (⌥)" }
        return "Drag, or hold ⌥ + move, to draw"
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Label(hintText, systemImage: tool == .select ? "cursorarrow" : (optionDown ? "pencil.tip" : "hand.draw"))
                .font(.caption)
                .foregroundStyle(optionDown && tool != .select ? Color.accentColor : .secondary)
            Divider().frame(height: 14)

            Button { setZoom(zoom - 0.25) } label: { Image(systemName: "minus.magnifyingglass") }
                .disabled(zoom <= Self.minZoom).help("Zoom out")
            Text("\(Int((zoom * 100).rounded()))%").font(.caption.monospacedDigit()).frame(minWidth: 42)
            Button { setZoom(zoom + 0.25) } label: { Image(systemName: "plus.magnifyingglass") }
                .disabled(zoom >= Self.maxZoom).help("Zoom in")
            Button("Fit Width") { fitWidth() }.help("Scale the page to fill the width")

            Divider().frame(height: 14)

            Button { paste() } label: { Image(systemName: "doc.on.clipboard") }
                .keyboardShortcut("v", modifiers: .command)
                .help("Paste image / screenshot (⌘V)")
            Button { importPDF() } label: { Image(systemName: "doc.badge.plus") }
                .help("Import a PDF as page backgrounds")
            Button { embedYouTube() } label: { Image(systemName: "play.rectangle") }
                .help("Embed a YouTube video (paste or type a link)")
            if markdownSource != nil {
                Button { syncFromMarkdown() } label: { Image(systemName: "doc.text.image") }
                    .help("Render the note's text as the background")
            }
            if (selectedImage != nil || selectedVideo != nil) && tool == .select {
                Button(role: .destructive) { deleteSelected() } label: { Image(systemName: "trash") }
                    .help("Delete selected item")
            }
            if importing { ProgressView().controlSize(.small) }

            Spacer()

            Text("\(pages.count) page\(pages.count == 1 ? "" : "s") · Letter")
                .font(.caption2).foregroundStyle(.tertiary)
            Button { addPage() } label: { Label("Add Page", systemImage: "plus") }
                .help("Add a blank page at the end")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: - Zoom

    private func setZoom(_ z: CGFloat) { zoom = min(max(z, Self.minZoom), Self.maxZoom) }
    private func fitWidth() {
        guard containerWidth > 0 else { return }
        setZoom((containerWidth - 64) / pageWidth)
        scrollTopToken += 1
    }

    /// Default to Fit Width the first time the canvas gets a real width, so
    /// switching to Draw lands at a readable full-width zoom without a tap.
    private func applyInitialFitIfNeeded() {
        guard !didInitialFit, containerWidth > 0 else { return }
        didInitialFit = true
        fitWidth()
    }

    // MARK: - Ink editing

    private func clamp(_ p: CGPoint, height: CGFloat) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), pageWidth), y: min(max(p.y, 0), height))
    }

    private func finalizeStroke(on i: Int) {
        if tool != .eraser, let s = current, pages.indices.contains(i) {
            pages[i].strokes.append(s)
            scheduleSave()
        }
        current = nil
    }

    private func undo() {
        guard pages.indices.contains(focusedPage), !pages[focusedPage].strokes.isEmpty else { return }
        pages[focusedPage].strokes.removeLast()
        scheduleSave()
    }

    private func clearPage() {
        guard pages.indices.contains(focusedPage), !pages[focusedPage].strokes.isEmpty else { return }
        pages[focusedPage].strokes.removeAll()
        scheduleSave()
    }

    private func eraseAt(_ p: CGPoint, page i: Int) {
        guard pages.indices.contains(i) else { return }
        let radius: CGFloat = 14
        let before = pages[i].strokes.count
        pages[i].strokes.removeAll { stroke in
            stroke.points.contains { hypot($0.x - p.x, $0.y - p.y) <= max(radius, stroke.width) }
        }
        if pages[i].strokes.count != before { scheduleSave() }
    }

    private func addPage() {
        current = nil
        pages.append(VMPage(strokes: [], background: nil, images: [], videos: []))
        focusedPage = pages.count - 1
        scheduleSave()
    }

    private func deleteSelected() {
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
        }
    }

    // MARK: - Insert image / PDF

    #if os(macOS)
    private func paste() {
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

    private func importPDF() {
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
    private func syncFromMarkdown() {
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
    private func embedYouTube() {
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

    private func loadThumb(_ id: String) {
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
    private func paste() {}
    private func importPDF() {}
    private func syncFromMarkdown() {}
    private func embedYouTube() {}
    private func loadThumb(_ id: String) {}
    #endif

    // MARK: - Persistence

    private func loadIfNeeded() {
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

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
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

    // MARK: - Modifier key (hold ⌥ to draw)

    #if os(macOS)
    private func installModifierMonitor() {
        optionDown = NSEvent.modifierFlags.contains(.option)
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            let down = event.modifierFlags.contains(.option)
            if !down, !isPressing { finalizeStroke(on: focusedPage) }
            optionDown = down
            return event
        }
    }
    private func removeModifierMonitor() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
    }
    #endif

    // MARK: - Rendering

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
