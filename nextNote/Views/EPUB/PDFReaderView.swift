#if os(macOS)
import SwiftUI
import SwiftData
import PDFKit

/// PDF counterpart to EPUBReaderView — now read **and** annotate.
///   - book.lastChapterIndex stores the current page index
///   - TOC drawer reuses EPUBTOCDrawer; spineIndex maps to a page number
///   - A tool bar drives freehand ink / highlighter / eraser, persisted by
///     writing PDFAnnotations back into the PDF file (`PDFDocument.write`).
struct PDFReaderView: View {
    @Bindable var book: Book
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    @State private var pdfDoc: PDFDocument?
    @State private var spine: [BookSpineEntry] = []
    @State private var toc: [BookTOCEntry] = []
    @State private var errorMessage: String?
    @State private var showTOC: Bool = false
    @State private var requestedPage: Int = 0

    // MARK: Annotation state
    @State private var fileURL: URL?
    @State private var annTool: PDFAnnTool = .hand
    @State private var annColor: PDFInkColor = .red
    @State private var penWidth: CGFloat = 2
    @State private var highlighterWidth: CGFloat = 14
    @State private var isDirty: Bool = false
    @State private var annError: String?

    private var pageCount: Int { pdfDoc?.pageCount ?? max(spine.count, 1) }
    private var currentIndex: Int { min(max(book.lastChapterIndex, 0), max(pageCount - 1, 0)) }

    var body: some View {
        Group {
            if let error = errorMessage {
                errorState(error)
            } else if let doc = pdfDoc {
                VStack(spacing: 0) {
                    toolbar
                    Divider()
                    annotationBar
                    Divider()
                    PDFKitView(
                        document: doc,
                        requestedPage: $requestedPage,
                        tool: annTool,
                        inkColor: annColor.nsColor(forTool: annTool),
                        lineWidth: annTool == .highlighter ? highlighterWidth : penWidth,
                        onPageChange: handlePageChange,
                        onEdited: { isDirty = true }
                    )
                    Divider()
                    bottomBar
                }
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: load)
        .onDisappear {
            if isDirty { saveAnnotations() }
            try? modelContext.save()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                showTOC.toggle()
            } label: {
                Image(systemName: "list.bullet.rectangle")
                    .accessibilityLabel("Table of Contents")
            }
            .help("Table of Contents (⌘⇧T)")
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .popover(isPresented: $showTOC, arrowEdge: .top) {
                EPUBTOCDrawer(
                    toc: toc,
                    spine: spine,
                    currentSpineIndex: currentIndex,
                    onJump: { idx, _ in
                        jumpToPage(idx)
                        showTOC = false
                    },
                    onClose: { showTOC = false }
                )
                .frame(width: 320, height: 480)
            }

            Spacer()

            Button {
                if let tabID = appState.openTabs.first(where: { $0.bookID == book.id })?.id {
                    appState.closeTab(id: tabID)
                }
            } label: {
                Image(systemName: "xmark")
                    .accessibilityLabel("Close Book")
            }
            .help("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var annotationBar: some View {
        HStack(spacing: 12) {
            Picker("Tool", selection: $annTool) {
                ForEach(PDFAnnTool.allCases) { t in
                    Image(systemName: t.icon).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            .help("Annotation tool")

            Picker("Color", selection: $annColor) {
                ForEach(PDFInkColor.allCases) { c in
                    Text(c.rawValue.capitalized).tag(c)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)
            .disabled(annTool == .hand || annTool == .eraser)

            HStack(spacing: 4) {
                Image(systemName: "lineweight")
                Slider(value: annTool == .highlighter ? $highlighterWidth : $penWidth, in: 1...30)
                    .frame(width: 90)
            }
            .disabled(annTool == .hand || annTool == .eraser)

            Spacer()

            if let annError {
                Text(annError).font(.caption).foregroundStyle(.red).lineLimit(1)
            }

            Button { saveAnnotations() } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(!isDirty)
            .help("Save annotations into the PDF")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var bottomBar: some View {
        HStack {
            Button {
                jumpToPage(currentIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .accessibilityLabel("Previous Page")
            }
            .help("Previous (⌘[)")
            .keyboardShortcut("[", modifiers: .command)
            .disabled(currentIndex <= 0)

            Spacer()

            Text("Page \(currentIndex + 1) / \(pageCount)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                jumpToPage(currentIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .accessibilityLabel("Next Page")
            }
            .help("Next (⌘])")
            .keyboardShortcut("]", modifiers: .command)
            .disabled(currentIndex >= pageCount - 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Close") {
                if let tabID = appState.openTabs.first(where: { $0.bookID == book.id })?.id {
                    appState.closeTab(id: tabID)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load / Save

    private func load() {
        guard let url = EPUBImporter.resolveFileURL(book.relativePath, vault: vault) else {
            errorMessage = "Couldn't find the PDF on disk."
            return
        }
        guard let doc = PDFDocument(url: url) else {
            errorMessage = "Could not open this PDF."
            return
        }
        fileURL = url
        pdfDoc = doc
        toc = (try? JSONDecoder().decode([BookTOCEntry].self, from: book.tocJSON)) ?? []
        spine = (try? JSONDecoder().decode([BookSpineEntry].self, from: book.spineJSON)) ?? []
        // If spine is empty (legacy / un-parsed), synthesize from page count.
        if spine.isEmpty {
            spine = (0..<doc.pageCount).map {
                BookSpineEntry(href: "page:\($0)", mediaType: "application/pdf")
            }
        }
        requestedPage = currentIndex
        book.lastOpenedAt = Date()
        try? modelContext.save()
    }

    private func saveAnnotations() {
        guard let doc = pdfDoc, let url = fileURL else { return }
        if doc.write(to: url) {
            isDirty = false
            annError = nil
        } else {
            annError = "Save failed"
        }
    }

    private func jumpToPage(_ idx: Int) {
        let clamped = min(max(idx, 0), max(pageCount - 1, 0))
        if book.lastChapterIndex != clamped {
            book.lastChapterIndex = clamped
            try? modelContext.save()
        }
        requestedPage = clamped
    }

    private func handlePageChange(_ idx: Int) {
        if book.lastChapterIndex != idx {
            book.lastChapterIndex = idx
        }
        // Keep requestedPage in lockstep with the page the user scrolled to,
        // so a SwiftUI re-render (annotating, dirty flag, etc.) doesn't make
        // updateNSView yank the view back to the old requestedPage.
        if requestedPage != idx {
            requestedPage = idx
        }
    }
}

// MARK: - Annotation tool model

enum PDFAnnTool: String, CaseIterable, Identifiable {
    case hand, pen, highlighter, eraser
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .hand:        return "hand.raised"
        case .pen:         return "pencil.tip"
        case .highlighter: return "highlighter"
        case .eraser:      return "eraser"
        }
    }
}

enum PDFInkColor: String, CaseIterable, Identifiable {
    case red, blue, black, green, yellow
    var id: String { rawValue }
    private var base: NSColor {
        switch self {
        case .red:    return .systemRed
        case .blue:   return .systemBlue
        case .black:  return .black
        case .green:  return .systemGreen
        case .yellow: return .systemYellow
        }
    }
    func nsColor(forTool tool: PDFAnnTool) -> NSColor {
        tool == .highlighter ? base.withAlphaComponent(0.3) : base
    }
}

// MARK: - Annotating PDFView

/// PDFView subclass that turns mouse drags into ink `PDFAnnotation`s on the
/// page under the cursor. Coordinate conversion uses PDFView's own
/// `page(for:nearest:)` + `convert(_:to:)` so points land in page space (no
/// manual Y-flip). When `tool == .hand` it defers to PDFView for normal
/// scroll / text selection.
final class AnnotatingPDFView: PDFView {
    var tool: PDFAnnTool = .hand
    var inkColor: NSColor = .systemRed
    var lineWidth: CGFloat = 2
    var onEdited: (() -> Void)?

    private struct StrokeRecord {
        let page: PDFPage
        let annotation: PDFAnnotation
        let bbox: CGRect
    }
    /// Session-scoped record of ink we added, with tight bounding boxes — used
    /// by the eraser to hit-test (annotations carry full-page bounds so we
    /// can't hit-test by `annotation.bounds`). Strokes from a previously-saved
    /// file aren't in this list (erasing those is a later enhancement).
    private var records: [StrokeRecord] = []
    private var drawingPage: PDFPage?
    private var pagePoints: [CGPoint] = []
    // Live preview: an overlay subview strokes the in-progress line in view
    // coords (instant feedback); the real PDFAnnotation is committed on mouseUp.
    private var overlayPoints: [CGPoint] = []
    private var strokeOverlay: StrokeOverlayView?

    private func pagePoint(for event: NSEvent, page forcedPage: PDFPage? = nil) -> (PDFPage, CGPoint)? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = forcedPage ?? self.page(for: viewPoint, nearest: true) else { return nil }
        return (page, convert(viewPoint, to: page))
    }

    override func mouseDown(with event: NSEvent) {
        switch tool {
        case .hand:
            super.mouseDown(with: event)
        case .pen, .highlighter:
            guard let (page, p) = pagePoint(for: event) else { return }
            drawingPage = page
            pagePoints = [p]
            overlayPoints = [convert(event.locationInWindow, from: nil)]
            updateOverlay()
        case .eraser:
            if let (page, p) = pagePoint(for: event) { eraseHit(p, on: page) }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        switch tool {
        case .hand:
            super.mouseDragged(with: event)
        case .pen, .highlighter:
            guard let page = drawingPage, let (_, p) = pagePoint(for: event, page: page) else { return }
            pagePoints.append(p)
            overlayPoints.append(convert(event.locationInWindow, from: nil))
            updateOverlay()
        case .eraser:
            if let (page, p) = pagePoint(for: event) { eraseHit(p, on: page) }
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch tool {
        case .hand:
            super.mouseUp(with: event)
        case .pen, .highlighter:
            if let page = drawingPage, !pagePoints.isEmpty {
                commitInk(on: page)
                onEdited?()
            }
            drawingPage = nil
            pagePoints = []
            overlayPoints = []
            strokeOverlay?.viewPoints = []
            strokeOverlay?.needsDisplay = true
        case .eraser:
            break
        }
    }

    private func updateOverlay() {
        if strokeOverlay == nil {
            let ov = StrokeOverlayView(frame: bounds)
            ov.autoresizingMask = [.width, .height]
            addSubview(ov)
            strokeOverlay = ov
        }
        guard let ov = strokeOverlay else { return }
        if ov.superview !== self || subviews.last !== ov {
            ov.removeFromSuperview()
            addSubview(ov)  // keep on top
        }
        ov.frame = bounds
        ov.strokeColor = inkColor
        ov.strokeWidth = max(1, lineWidth * scaleFactor)
        ov.viewPoints = overlayPoints
        ov.needsDisplay = true
    }

    private func commitInk(on page: PDFPage) {
        let annotation = PDFAnnotation(bounds: page.bounds(for: .mediaBox), forType: .ink, withProperties: nil)
        let border = PDFBorder()
        border.lineWidth = lineWidth
        annotation.border = border
        annotation.color = inkColor

        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if pagePoints.count == 1 {
            let f = pagePoints[0]
            path.appendOval(in: CGRect(x: f.x - lineWidth / 2, y: f.y - lineWidth / 2,
                                       width: lineWidth, height: lineWidth))
        } else {
            path.move(to: pagePoints[0])
            for q in pagePoints.dropFirst() { path.line(to: q) }
        }
        annotation.add(path)
        page.addAnnotation(annotation)
        records.append(StrokeRecord(page: page, annotation: annotation,
                                    bbox: boundingBox(pagePoints, pad: max(lineWidth, 8))))
    }

    private func eraseHit(_ p: CGPoint, on page: PDFPage) {
        let hits = records.filter { $0.page === page && $0.bbox.contains(p) }
        guard !hits.isEmpty else { return }
        for rec in hits { page.removeAnnotation(rec.annotation) }
        let removed = Set(hits.map { ObjectIdentifier($0.annotation) })
        records.removeAll { removed.contains(ObjectIdentifier($0.annotation)) }
        onEdited?()
    }

    private func boundingBox(_ points: [CGPoint], pad: CGFloat) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX - pad, y: minY - pad,
                      width: (maxX - minX) + pad * 2, height: (maxY - minY) + pad * 2)
    }
}

/// Transparent overlay that strokes the in-progress line in the PDFView's
/// own (view) coordinates for instant feedback. Returns nil from hitTest so
/// all mouse events still reach the PDFView underneath.
final class StrokeOverlayView: NSView {
    var viewPoints: [CGPoint] = []
    var strokeColor: NSColor = .systemRed
    var strokeWidth: CGFloat = 2

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard !viewPoints.isEmpty else { return }
        let path = NSBezierPath()
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if viewPoints.count == 1 {
            let f = viewPoints[0]
            let r = CGRect(x: f.x - strokeWidth/2, y: f.y - strokeWidth/2, width: strokeWidth, height: strokeWidth)
            strokeColor.setFill()
            NSBezierPath(ovalIn: r).fill()
        } else {
            path.move(to: viewPoints[0])
            for p in viewPoints.dropFirst() { path.line(to: p) }
            strokeColor.setStroke()
            path.stroke()
        }
    }
}

/// NSViewRepresentable wrapper around AnnotatingPDFView. External code drives
/// navigation via `requestedPage`; internal page changes report back via
/// `onPageChange`; edits flip `onEdited`.
struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var requestedPage: Int
    var tool: PDFAnnTool
    var inkColor: NSColor
    var lineWidth: CGFloat
    let onPageChange: (Int) -> Void
    let onEdited: () -> Void

    func makeNSView(context: Context) -> AnnotatingPDFView {
        let view = AnnotatingPDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor.windowBackgroundColor
        view.tool = tool
        view.inkColor = inkColor
        view.lineWidth = lineWidth
        view.onEdited = onEdited
        if let page = document.page(at: requestedPage) {
            view.go(to: page)
        }
        context.coordinator.attach(view: view)
        return view
    }

    func updateNSView(_ view: AnnotatingPDFView, context: Context) {
        view.tool = tool
        view.inkColor = inkColor
        view.lineWidth = lineWidth
        view.onEdited = onEdited
        guard let target = document.page(at: requestedPage) else { return }
        if view.currentPage != target {
            view.go(to: target)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: PDFKitView
        weak var view: PDFView?

        init(parent: PDFKitView) {
            self.parent = parent
            super.init()
        }

        func attach(view: PDFView) {
            self.view = view
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged(_:)),
                name: .PDFViewPageChanged,
                object: view
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func pageChanged(_ note: Notification) {
            guard let view = view, let page = view.currentPage else { return }
            let idx = view.document?.index(for: page) ?? 0
            parent.onPageChange(idx)
        }
    }
}
#endif
