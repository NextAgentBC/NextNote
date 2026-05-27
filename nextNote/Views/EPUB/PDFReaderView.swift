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
// AnnotatingPDFView, StrokeOverlayView, PDFAnnTool, PDFInkColor → see
// `PDFReaderAnnotation.swift`. The NSViewRepresentable shell that wraps
// the AppKit PDFView → see `PDFKitView.swift`.
#endif
