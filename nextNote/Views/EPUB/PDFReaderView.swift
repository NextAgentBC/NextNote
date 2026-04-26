#if os(macOS)
import SwiftUI
import SwiftData
import PDFKit

/// PDF counterpart to EPUBReaderView. Same mental model:
///   - book.lastChapterIndex stores the current page index
///   - book.lastScrollRatio kept (unused for now, reserved for in-page scroll)
///   - TOC drawer reuses EPUBTOCDrawer; spineIndex on each entry maps
///     to a page number, jump = PDFView.go(to:)
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
                    PDFKitView(
                        document: doc,
                        requestedPage: $requestedPage,
                        onPageChange: handlePageChange
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
        .onDisappear { try? modelContext.save() }
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

    // MARK: - Load

    private func load() {
        guard let url = EPUBImporter.resolveFileURL(book.relativePath, vault: vault) else {
            errorMessage = "Couldn't find the PDF on disk."
            return
        }
        guard let doc = PDFDocument(url: url) else {
            errorMessage = "Could not open this PDF."
            return
        }
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

    private func jumpToPage(_ idx: Int) {
        let clamped = min(max(idx, 0), max(pageCount - 1, 0))
        if book.lastChapterIndex != clamped {
            book.lastChapterIndex = clamped
            try? modelContext.save()
        }
        requestedPage = clamped
    }

    private func handlePageChange(_ idx: Int) {
        // Persist scroll progress as user pages through.
        if book.lastChapterIndex != idx {
            book.lastChapterIndex = idx
        }
    }
}

/// Minimal NSViewRepresentable wrapper around PDFView. External code
/// drives navigation via the `requestedPage` binding; internal page
/// changes (user scroll / next-page key) report back via `onPageChange`.
struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var requestedPage: Int
    let onPageChange: (Int) -> Void

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor.windowBackgroundColor
        if let page = document.page(at: requestedPage) {
            view.go(to: page)
        }
        context.coordinator.attach(view: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
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
