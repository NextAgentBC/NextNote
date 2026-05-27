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
///
/// This file holds the view shell (state, body, toolbar, page rendering,
/// bottom bar, zoom, modifier monitor). The four `+` siblings hold:
///   - `+Editing.swift`     — ink mutation + lasso selection
///   - `+Media.swift`       — paste / PDF import / YouTube embed / md sync
///   - `+Persistence.swift` — load / debounced autosave
///   - `+Rendering.swift`   — static stroke / smoothing helpers
struct DrawingDocumentView: View {
    let fileURL: URL
    /// When this drawing is the "Draw" layer of a markdown note, its rendered
    /// text can be loaded as the page background(s) to annotate over.
    var markdownSource: String? = nil
    var markdownBaseURL: URL? = nil

    enum Tool: String, CaseIterable, Identifiable {
        case select, pen, highlighter, eraser, lasso
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .select:      return "cursorarrow"
            case .pen:         return "pencil.tip"
            case .highlighter: return "highlighter"
            case .eraser:      return "eraser"
            case .lasso:       return "lasso"
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

    // Nested helper types — kept internal (not `private`) so the `+Editing` /
    // `+Persistence` / `+Media` extensions in sibling files can name them.
    struct VMPage {
        var strokes: [DrawStroke]
        var background: String?
        var images: [PlacedImage]
        var videos: [PlacedVideo]
    }
    struct ImgSel: Equatable { var page: Int; var index: Int }
    struct VidSel: Equatable { var page: Int; var index: Int }
    enum LassoMode { case draw, move }

    private static let minZoom: CGFloat = 0.25
    private static let maxZoom: CGFloat = 4.0

    // @State declared without `private` so cross-file extensions can mutate.
    // Encapsulation is at the type level — nothing outside this view touches
    // these.
    @State var pages: [VMPage] = [VMPage(strokes: [], background: nil, images: [], videos: [])]
    @State var bgCache: [Int: NSImage] = [:]
    @State var imgCache: [String: NSImage] = [:]
    @State var current: DrawStroke?
    @State var focusedPage: Int = 0
    @State var pageWidth: CGFloat = CGFloat(DrawingDoc.letterWidth)
    @State var pageHeight: CGFloat = CGFloat(DrawingDoc.letterHeight)
    @State var tool: Tool = .pen
    @State var inkColor: InkColor = .black
    @State var penWidth: CGFloat = 3
    @State var highlighterWidth: CGFloat = 16
    @State var zoom: CGFloat = 1.0
    @State var containerWidth: CGFloat = 0
    @State var scrollTopToken = 0
    @State var didInitialFit = false
    @State var importing = false
    @State var loaded = false
    @State var saveError: String?
    @State var saveTask: Task<Void, Never>?
    @State var optionDown = false
    @State var isPressing = false
    @State var selectedImage: ImgSel?
    @State var imgBaseline: CGPoint?
    @State var selectedVideo: VidSel?
    @State var vidBaseline: CGPoint?
    @State var playingVideo: VidSel?
    @State var thumbCache: [String: NSImage] = [:]
    // Lasso selection of ink strokes (operates on the focused page).
    @State var lassoPoints: [CGPoint] = []
    @State var strokeSel: Set<Int> = []
    @State var lassoPage: Int?
    @State var lassoMode: LassoMode?
    @State var moveStart: CGPoint?
    @State var moveSnapshot: [Int: [CGPoint]]?
    // Shape-recognition toggle (snaps pen strokes to line/rect/ellipse/triangle).
    @State var snapShapes = false
    #if os(macOS)
    @State var flagsMonitor: Any?
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
        .onChange(of: tool) { _, t in
            if t != .select { selectedImage = nil; selectedVideo = nil; playingVideo = nil }
            if t != .lasso { strokeSel = []; lassoPage = nil; lassoPoints = []; lassoMode = nil }
        }
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
            .pickerStyle(.segmented).labelsHidden().frame(width: 210).help("Tool")

            Picker("Color", selection: $inkColor) {
                ForEach(InkColor.allCases) { c in Text(c.rawValue.capitalized).tag(c) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 280)
            .disabled((!tool.isDrawing && tool != .lasso) || tool == .eraser)

            HStack(spacing: 4) {
                Image(systemName: "lineweight")
                Slider(value: tool == .highlighter ? $highlighterWidth : $penWidth, in: 1...40)
                    .frame(width: 100)
            }
            .disabled(!tool.isDrawing || tool == .eraser)

            Toggle(isOn: $snapShapes) { Image(systemName: "square.on.circle") }
                .toggleStyle(.button)
                .help("Snap shapes: pen strokes become a clean line / rectangle / ellipse / triangle")

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
                    for (idx, s) in pages[i].strokes.enumerated() {
                        if lassoPage == i, strokeSel.contains(idx) { Self.drawHalo(stroke: s, in: ctx) }
                        Self.draw(stroke: s, in: ctx)
                    }
                }
                if i == focusedPage, let s = current { Self.draw(stroke: s, in: ctx) }
                if lassoPage == i, !strokeSel.isEmpty, let box = selectionBox(page: i) {
                    ctx.stroke(Path(roundedRect: box.insetBy(dx: -6, dy: -6), cornerRadius: 6),
                               with: .color(.accentColor),
                               style: StrokeStyle(lineWidth: 1 / zoom, dash: [5 / zoom, 4 / zoom]))
                }
                if i == focusedPage, tool == .lasso, lassoPoints.count > 1 {
                    var lp = Path()
                    lp.move(to: lassoPoints[0])
                    for p in lassoPoints.dropFirst() { lp.addLine(to: p) }
                    ctx.stroke(lp, with: .color(.accentColor.opacity(0.8)),
                               style: StrokeStyle(lineWidth: 1 / zoom, dash: [6 / zoom, 4 / zoom]))
                }
            }
            .frame(width: pageWidth * zoom, height: h * zoom)
            .allowsHitTesting(tool != .select)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let loc):
                    guard optionDown, !isPressing, tool.isDrawing else { return }
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
                        if tool == .lasso { lassoChanged(p, page: i); return }
                        if tool == .eraser { eraseAt(p, page: i); return }
                        if tool == .pen || tool == .highlighter {
                            if current == nil {
                                current = DrawStroke(points: [p], color: activeColor, width: activeWidth)
                            } else {
                                current?.points.append(p)
                            }
                        }
                    }
                    .onEnded { _ in
                        if tool == .lasso { lassoEnded(page: i) } else { finalizeStroke(on: i) }
                        isPressing = false
                    }
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
        if tool == .lasso {
            return strokeSel.isEmpty
                ? "Lasso: circle strokes to select"
                : "Selected \(strokeSel.count) — drag inside to move · ⌫ delete · pick a color then recolor"
        }
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
            if tool == .lasso, lassoPage != nil, !strokeSel.isEmpty {
                Button { recolorSelection() } label: { Image(systemName: "paintbrush") }
                    .help("Recolor selection to the current color")
                Button(role: .destructive) { deleteSelected() } label: { Image(systemName: "trash") }
                    .help("Delete selection (⌫)")
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
}
