import SwiftUI
import SwiftData

struct EPUBReaderView: View {
    @Bindable var book: Book
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    @State private var unzipRoot: URL?
    @State private var contentBase: URL?
    @State private var toc: [BookTOCEntry] = []
    @State private var spine: [BookSpineEntry] = []
    @State private var errorMessage: String?
    @State private var showHighlights: Bool = false
    @State private var showTOC: Bool = false
    @StateObject private var pager = EPUBPager()
    @FocusState private var readerFocused: Bool
    @State private var pendingAnchor: String?

    @Query private var allHighlights: [BookHighlight]

    private var chapterHighlights: [BookHighlight] {
        let bookID = book.id
        let href = currentChapterHref
        return allHighlights.filter { $0.bookID == bookID && $0.chapterHref == href }
    }

    private var bookHighlights: [BookHighlight] {
        let bookID = book.id
        return allHighlights.filter { $0.bookID == bookID }
    }

    private var currentIndex: Int {
        min(max(book.lastChapterIndex, 0), max(spine.count - 1, 0))
    }

    private var currentChapterHref: String {
        guard !spine.isEmpty else { return "" }
        return spine[currentIndex].href
    }

    private var currentChapterURL: URL? {
        guard let base = contentBase, !currentChapterHref.isEmpty else { return nil }
        // Strip anchor fragment — WKWebView loadFileURL can't take fragments.
        let cleanHref = currentChapterHref.split(separator: "#").first.map(String.init) ?? currentChapterHref
        return base.appendingPathComponent(cleanHref)
    }

    private var theme: BookTheme {
        BookTheme(rawValue: book.themeRaw) ?? .light
    }

    var body: some View {
        Group {
            if let error = errorMessage {
                errorState(error)
            } else if let chapterURL = currentChapterURL,
                      let root = unzipRoot {
                VStack(spacing: 0) {
                    readerToolbar
                    Divider()
                    EPUBContentWebView(
                        chapterURL: chapterURL,
                        readAccessRoot: root,
                        fontSize: book.fontSize,
                        theme: theme,
                        initialScrollRatio: book.lastScrollRatio,
                        pendingAnchor: pendingAnchor,
                        highlights: chapterHighlights,
                        onSelectionHighlight: handleHighlightSelection,
                        onScroll: handleScroll,
                        onPageBoundary: handleBoundary,
                        onInternalLink: handleInternalLink,
                        pager: pager
                    )
                    .focusable()
                    .focused($readerFocused)
                    .onAppear { readerFocused = true }
                    #if os(macOS)
                    .onKeyPress(keys: [.space, .rightArrow, .downArrow, .pageDown]) { _ in
                        pager.page(.pageDown); return .handled
                    }
                    .onKeyPress(keys: [.leftArrow, .upArrow, .pageUp]) { _ in
                        pager.page(.pageUp); return .handled
                    }
                    #endif
                    Divider()
                    bottomBar
                }
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: load)
        .onAppear { syncAnchorFromAppState() }
        .onChange(of: appState.pendingBookAnchor) { _, _ in syncAnchorFromAppState() }
        .onDisappear {
            try? modelContext.save()
        }
        .sheet(isPresented: $showHighlights) {
            HighlightsPanel(
                book: book,
                spine: spine,
                highlights: bookHighlights,
                onJump: { idx in
                    if let i = idx {
                        setChapter(i)
                        showHighlights = false
                    }
                },
                onDelete: { h in
                    modelContext.delete(h)
                    try? modelContext.save()
                }
            )
            .frame(minWidth: 420, minHeight: 380)
        }
    }

    // MARK: - Load

    private func load() {
        do {
            let root = try EPUBImporter.ensureUnzipped(book, vault: vault)
            let contentDir = root.appendingPathComponent(
                (book.opfRelativePath as NSString).deletingLastPathComponent,
                isDirectory: true
            )
            var decodedTOC = (try? JSONDecoder().decode([BookTOCEntry].self, from: book.tocJSON)) ?? []
            var decodedSpine = (try? JSONDecoder().decode([BookSpineEntry].self, from: book.spineJSON)) ?? []

            // Recover from imports that landed an empty TOC OR a TOC
            // saved before spineIndex resolution shipped — re-parse from
            // the unzipped EPUB so chapter jumps work without manual
            // "Refresh Table of Contents" action.
            let needsRefresh = decodedTOC.isEmpty
                || decodedSpine.isEmpty
                || !Self.tocHasResolvedIndex(decodedTOC)
            if needsRefresh {
                _ = EPUBImporter.refreshMetadata(book, vault: vault)
                decodedTOC = (try? JSONDecoder().decode([BookTOCEntry].self, from: book.tocJSON)) ?? []
                decodedSpine = (try? JSONDecoder().decode([BookSpineEntry].self, from: book.spineJSON)) ?? []
            }

            self.unzipRoot = root
            self.contentBase = contentDir
            self.toc = decodedTOC
            self.spine = decodedSpine
            if decodedSpine.isEmpty {
                self.errorMessage = "This EPUB has no readable chapters."
                return
            }
            book.lastOpenedAt = Date()
            try? modelContext.save()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sidebars and bars

    private var readerToolbar: some View {
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
                    onJump: { idx, anchor in
                        jumpToSpine(idx, anchor: anchor)
                        showTOC = false
                    },
                    onClose: { showTOC = false }
                )
                .frame(width: 320, height: 480)
            }

            // Title is shown in the window chrome — no need to duplicate
            // it here. Leave the leading edge clean for toolbar controls.
            Spacer()

            Menu {
                ForEach(BookTheme.allCases) { t in
                    Button {
                        book.themeRaw = t.rawValue
                        try? modelContext.save()
                    } label: {
                        if theme == t {
                            Label(t.displayName, systemImage: "checkmark")
                        } else {
                            Text(t.displayName)
                        }
                    }
                }
            } label: {
                Image(systemName: "paintpalette")
                    .accessibilityLabel("Theme")
            }
            .help("Theme")

            Button {
                book.fontSize = max(12, book.fontSize - 1)
                try? modelContext.save()
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .accessibilityLabel("Smaller Text")
            }
            .help("Smaller text")

            Button {
                book.fontSize = min(28, book.fontSize + 1)
                try? modelContext.save()
            } label: {
                Image(systemName: "textformat.size.larger")
                    .accessibilityLabel("Bigger Text")
            }
            .help("Bigger text")

            Button {
                showHighlights = true
            } label: {
                Image(systemName: "highlighter")
                    .accessibilityLabel("Highlights")
            }
            .help("Highlights")

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
                if currentIndex > 0 { goToChapter(currentIndex - 1) }
            } label: {
                Image(systemName: "chevron.left")
                    .accessibilityLabel("Previous Chapter")
            }
            .help("Previous Chapter (⌘[)")
            .disabled(currentIndex == 0)
            .keyboardShortcut("[", modifiers: .command)

            Button {
                pager.page(.pageUp)
            } label: {
                Image(systemName: "arrow.up.to.line.compact")
                    .accessibilityLabel("Page Up")
            }
            .help("Page up (↑ / shift-space)")

            Spacer()

            Text("Chapter \(currentIndex + 1) / \(spine.count) · \(Int(book.lastScrollRatio * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                pager.page(.pageDown)
            } label: {
                Image(systemName: "arrow.down.to.line.compact")
                    .accessibilityLabel("Page Down")
            }
            .help("Page down (↓ / space)")

            Button {
                if currentIndex < spine.count - 1 { goToChapter(currentIndex + 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .accessibilityLabel("Next Chapter")
            }
            .help("Next Chapter (⌘])")
            .disabled(currentIndex >= spine.count - 1)
            .keyboardShortcut("]", modifiers: .command)
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

    // MARK: - Actions

    private func setChapter(_ idx: Int) {
        guard idx >= 0, idx < spine.count else { return }
        book.lastChapterIndex = idx
        book.lastScrollRatio = 0
        try? modelContext.save()
    }

    private func goToChapter(_ idx: Int) {
        pendingAnchor = nil
        setChapter(idx)
    }

    /// True iff at least one TOC entry (recursively) has a resolved
    /// `spineIndex`. Books imported before spineIndex resolution shipped
    /// have all-nil values; that's the trigger for an auto-refresh on
    /// open so the user doesn't see a TOC where every row is greyed out.
    private static func tocHasResolvedIndex(_ entries: [BookTOCEntry]) -> Bool {
        for e in entries {
            if e.spineIndex != nil { return true }
            if tocHasResolvedIndex(e.children) { return true }
        }
        return false
    }

    /// TOC drawer click handler — pre-resolved spine index makes this a
    /// plain integer jump, no path matching needed.
    private func jumpToSpine(_ idx: Int, anchor: String?) {
        guard idx >= 0, idx < spine.count else { return }
        appState.pendingBookAnchor = anchor
        if book.lastChapterIndex != idx {
            book.lastChapterIndex = idx
            book.lastScrollRatio = 0
        } else if anchor != nil {
            // Same chapter, anchor jump only.
            book.lastScrollRatio = 0
        }
        pendingAnchor = anchor
        try? modelContext.save()
    }

    private func syncAnchorFromAppState() {
        pendingAnchor = appState.pendingBookAnchor
    }

    private func handleScroll(_ ratio: Double) {
        // Debounce light — persist only when it moves materially.
        if abs(ratio - book.lastScrollRatio) > 0.01 {
            book.lastScrollRatio = ratio
        }
    }

    private func handleBoundary(_ edge: EPUBContentWebView.PageBoundary) {
        switch edge {
        case .atEnd:
            if currentIndex < spine.count - 1 { goToChapter(currentIndex + 1) }
        case .atStart:
            if currentIndex > 0 { goToChapter(currentIndex - 1) }
        }
    }

    /// Resolve an `<a href>` click inside a chapter to the spine entry that
    /// owns that XHTML file, then jump. Anchor (if any) is forwarded via
    /// appState.pendingBookAnchor so the webview scrolls there once the
    /// new chapter loads.
    private func handleInternalLink(filename: String, anchor: String?) {
        guard let idx = spine.firstIndex(where: {
            let sh = $0.href.split(separator: "#").first.map(String.init) ?? $0.href
            return (sh as NSString).lastPathComponent == filename
        }) else { return }
        appState.pendingBookAnchor = anchor
        if book.lastChapterIndex != idx {
            book.lastChapterIndex = idx
            book.lastScrollRatio = 0
            try? modelContext.save()
        } else if let anchor {
            // Already on this chapter — anchor change alone won't trigger
            // updateNSView via lastChapterIndex, but the @State pendingAnchor
            // sync will fire from onChange(of: appState.pendingBookAnchor).
            pendingAnchor = anchor
        }
    }

    private func handleHighlightSelection(_ payload: EPUBContentWebView.HighlightPayload) {
        let highlight = BookHighlight(
            bookID: book.id,
            chapterHref: currentChapterHref,
            chapterIndex: currentIndex,
            selectedText: payload.text,
            rangeStart: payload.rangeStart,
            rangeEnd: payload.rangeEnd
        )
        modelContext.insert(highlight)
        try? modelContext.save()
    }

}

// MARK: - Highlights panel

struct HighlightsPanel: View {
    let book: Book
    let spine: [BookSpineEntry]
    let highlights: [BookHighlight]
    var onJump: (Int?) -> Void
    var onDelete: (BookHighlight) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Highlights")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            Divider()
            if highlights.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "highlighter")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No highlights yet")
                        .foregroundStyle(.secondary)
                    Text("Select text in the book to create one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(highlights.sorted(by: {
                        ($0.chapterIndex, $0.rangeStart) < ($1.chapterIndex, $1.rangeStart)
                    })) { h in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Chapter \(h.chapterIndex + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(h.selectedText)
                                .lineLimit(4)
                            HStack {
                                Button("Jump") { onJump(h.chapterIndex) }
                                    .buttonStyle(.borderless)
                                Spacer()
                                Button(role: .destructive) {
                                    onDelete(h)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}
