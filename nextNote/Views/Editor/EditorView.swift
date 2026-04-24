import SwiftUI

struct EditorView: View {
    @Bindable var document: TextDocument
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var prefs = UserPreferences.shared

    var body: some View {
        PlatformTextEditor(
            text: $document.content,
            isMarkdown: document.fileType == .md,
            insertionRequest: Binding(
                get: { appState.pendingSnippet },
                set: { appState.pendingSnippet = $0 }
            ),
            onTextChange: {
                document.modifiedAt = Date()
                markTabModified()
            },
            fontName: prefs.fontName,
            fontSize: CGFloat(prefs.fontSize),
            lineSpacing: CGFloat(prefs.lineSpacing),
            wrapLines: prefs.wrapLines
        )
        .id(document.fileTypeRaw) // Force recreate editor when file type changes
    }

    private func markTabModified() {
        if let index = appState.openTabs.firstIndex(where: { $0.document.id == document.id }) {
            appState.openTabs[index].isModified = true
        }
    }
}

// MARK: - Platform Text Editor Wrapper

struct PlatformTextEditor: View {
    @Binding var text: String
    let isMarkdown: Bool
    @Binding var insertionRequest: SnippetInsert?
    var onTextChange: (() -> Void)?

    let fontName: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let wrapLines: Bool

    var body: some View {
        #if os(macOS)
        MacTextEditorView(
            text: $text,
            isMarkdown: isMarkdown,
            insertionRequest: $insertionRequest,
            onTextChange: onTextChange,
            fontName: fontName,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            wrapLines: wrapLines
        )
        #else
        iOSTextEditorView(
            text: $text,
            isMarkdown: isMarkdown,
            insertionRequest: $insertionRequest,
            onTextChange: onTextChange,
            fontName: fontName,
            fontSize: fontSize,
            lineSpacing: lineSpacing
        )
        #endif
    }
}

// MARK: - Shared font / paragraph style helpers

#if os(macOS)
func resolveFont(name: String, size: CGFloat) -> NSFont {
    switch name {
    case "SF Mono":  return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    case "SF Pro":   return NSFont.systemFont(ofSize: size)
    case "New York": return NSFont(name: "NewYorkMedium-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
    case "Menlo":    return NSFont(name: "Menlo-Regular", size: size)         ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    case "Courier":  return NSFont(name: "Courier", size: size)               ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    default:         return NSFont(name: name, size: size)                    ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

func makeParagraphStyle(lineSpacing: CGFloat) -> NSMutableParagraphStyle {
    let s = NSMutableParagraphStyle()
    s.lineHeightMultiple = lineSpacing
    return s
}
#endif

#if os(iOS)
func resolveFont(name: String, size: CGFloat) -> UIFont {
    switch name {
    case "SF Mono":  return UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    case "SF Pro":   return UIFont.systemFont(ofSize: size)
    case "New York": return UIFont(name: "NewYorkMedium-Regular", size: size) ?? UIFont.systemFont(ofSize: size)
    case "Menlo":    return UIFont(name: "Menlo-Regular", size: size)         ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    case "Courier":  return UIFont(name: "Courier", size: size)               ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    default:         return UIFont(name: name, size: size)                    ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

func makeParagraphStyle(lineSpacing: CGFloat) -> NSMutableParagraphStyle {
    let s = NSMutableParagraphStyle()
    s.lineHeightMultiple = lineSpacing
    return s
}
#endif

// MARK: - iOS Text Editor

#if os(iOS)
struct iOSTextEditorView: UIViewRepresentable {
    @Binding var text: String
    let isMarkdown: Bool
    @Binding var insertionRequest: SnippetInsert?
    var onTextChange: (() -> Void)?

    let fontName: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .default
        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        context.coordinator.textView = textView
        applyTypingAttributes(to: textView)
        applyContent(to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Handle pending snippet insert (undo-safe via UITextView.replace)
        if let snippet = insertionRequest {
            insertionRequest = nil  // clear before insert to avoid re-entry
            context.coordinator.insertAtCursor(snippet, in: textView)
            return  // text/preferences will be synced in the next update cycle
        }

        context.coordinator.parent = self

        let coord = context.coordinator
        let prefsChanged = coord.lastFontName    != fontName
                        || coord.lastFontSize    != fontSize
                        || coord.lastLineSpacing != lineSpacing

        if textView.text != text || coord.lastIsMarkdown != isMarkdown || prefsChanged {
            coord.lastIsMarkdown  = isMarkdown
            coord.lastFontName    = fontName
            coord.lastFontSize    = fontSize
            coord.lastLineSpacing = lineSpacing

            let sel = textView.selectedRange
            applyTypingAttributes(to: textView)
            applyContent(to: textView)
            if sel.location + sel.length <= textView.text.count {
                textView.selectedRange = sel
            }
        }
    }

    private func applyTypingAttributes(to textView: UITextView) {
        let font = resolveFont(name: fontName, size: fontSize)
        let para = makeParagraphStyle(lineSpacing: lineSpacing)
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: para,
        ]
    }

    private func applyContent(to textView: UITextView) {
        let font = resolveFont(name: fontName, size: fontSize)
        let para = makeParagraphStyle(lineSpacing: lineSpacing)
        if isMarkdown {
            let attributed = MarkdownHighlighter.highlight(text, fontSize: fontSize)
            attributed.addAttribute(.paragraphStyle, value: para,
                                    range: NSRange(location: 0, length: attributed.length))
            textView.attributedText = attributed
        } else {
            textView.attributedText = NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: UIColor.label,
                .paragraphStyle: para,
            ])
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: iOSTextEditorView
        weak var textView: UITextView?
        var lastIsMarkdown  = false
        var lastFontName    = ""
        var lastFontSize    = CGFloat(0)
        var lastLineSpacing = CGFloat(0)

        init(_ parent: iOSTextEditorView) {
            self.parent = parent
        }

        /// Insert text at the current cursor position (or replace selection).
        /// Uses UITextView.replace which is tracked by the system undo manager.
        func insertAtCursor(_ snippet: SnippetInsert, in textView: UITextView) {
            let range = textView.selectedTextRange ?? textView.textRange(
                from: textView.endOfDocument, to: textView.endOfDocument
            )!
            let insertStart = range.start
            textView.replace(range, withText: snippet.text)

            // Position cursor at cursorOffset within the inserted text
            if let newPos = textView.position(from: insertStart, offset: snippet.cursorOffset),
               let newRange = textView.textRange(from: newPos, to: newPos) {
                textView.selectedTextRange = newRange
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.onTextChange?()

            if parent.isMarkdown {
                let sel = textView.selectedRange
                let attributed = MarkdownHighlighter.highlight(textView.text, fontSize: parent.fontSize)
                let para = makeParagraphStyle(lineSpacing: parent.lineSpacing)
                attributed.addAttribute(.paragraphStyle, value: para,
                                        range: NSRange(location: 0, length: attributed.length))
                textView.attributedText = attributed
                if sel.location + sel.length <= textView.text.count {
                    textView.selectedRange = sel
                }
            }
        }
    }
}
#endif

// MARK: - macOS Text Editor

#if os(macOS)
struct MacTextEditorView: NSViewRepresentable {
    @Binding var text: String
    let isMarkdown: Bool
    @Binding var insertionRequest: SnippetInsert?
    var onTextChange: (() -> Void)?

    let fontName: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let wrapLines: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = true
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 20, height: 16)

        textView.registerForDraggedTypes([.fileURL, .png, .tiff])

        context.coordinator.textView = textView
        applyWrapLines(wrapLines, to: textView)
        context.coordinator.applyText(text, isMarkdown: isMarkdown)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Handle pending snippet insert first (undo-safe via NSTextView.insertText)
        if let snippet = insertionRequest {
            insertionRequest = nil  // clear before insert to avoid re-entry
            context.coordinator.insertAtCursor(snippet, in: textView)
            return  // text/preferences will be synced in the next update cycle
        }

        let coordinator = context.coordinator
        coordinator.parent = self

        let prefsChanged = coordinator.lastFontName    != fontName
                        || coordinator.lastFontSize    != fontSize
                        || coordinator.lastLineSpacing != lineSpacing

        if coordinator.lastText != text || coordinator.lastIsMarkdown != isMarkdown || prefsChanged {
            coordinator.isUpdating = true
            coordinator.applyText(text, isMarkdown: isMarkdown)
            coordinator.isUpdating = false
        }

        if coordinator.lastWrapLines != wrapLines {
            applyWrapLines(wrapLines, to: textView)
            coordinator.lastWrapLines = wrapLines
        }
    }

    // MARK: - Wrap lines

    private func applyWrapLines(_ wrap: Bool, to textView: NSTextView) {
        if wrap {
            textView.textContainer?.widthTracksTextView = true
            textView.isHorizontallyResizable = false
            textView.textContainer?.containerSize = NSSize(
                width: textView.enclosingScrollView?.contentView.bounds.width ?? 800,
                height: CGFloat.greatestFiniteMagnitude
            )
        } else {
            textView.textContainer?.widthTracksTextView = false
            textView.isHorizontallyResizable = true
            textView.textContainer?.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate, NSDraggingDestination {
        var parent: MacTextEditorView
        weak var textView: NSTextView?
        var lastText: String      = ""
        var lastIsMarkdown: Bool  = false
        var lastFontName: String  = ""
        var lastFontSize: CGFloat = 0
        var lastLineSpacing: CGFloat = 0
        var lastWrapLines: Bool   = true
        var isUpdating: Bool      = false

        /// Legacy image-only set — kept for reference but drop logic now
        /// accepts any `MediaKind` (image + video + audio) so the Asset
        /// Library, Finder, and YouTube-download flows all converge on the
        /// same embed syntax.
        private let imageExtensions: Set<String> = MediaKind.imageExts

        init(_ parent: MacTextEditorView) {
            self.parent = parent
        }

        // MARK: - Apply text + preferences

        func applyText(_ text: String, isMarkdown: Bool) {
            guard let textView = textView else { return }

            lastText        = text
            lastIsMarkdown  = isMarkdown
            lastFontName    = parent.fontName
            lastFontSize    = parent.fontSize
            lastLineSpacing = parent.lineSpacing

            let selectedRanges = textView.selectedRanges
            let font = resolveFont(name: parent.fontName, size: parent.fontSize)
            let para = makeParagraphStyle(lineSpacing: parent.lineSpacing)

            let attributed: NSMutableAttributedString
            if isMarkdown {
                attributed = MarkdownHighlighter.highlightMac(text, fontSize: parent.fontSize)
            } else {
                attributed = NSMutableAttributedString(
                    string: text,
                    attributes: [.font: font, .foregroundColor: NSColor.textColor]
                )
            }
            attributed.addAttribute(.paragraphStyle, value: para,
                                    range: NSRange(location: 0, length: attributed.length))

            textView.textStorage?.setAttributedString(attributed)
            textView.typingAttributes = [
                .font: font,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: para,
            ]
            textView.selectedRanges = selectedRanges
        }

        // MARK: - Snippet insert (undo-safe)

        /// Insert snippet.text at the current cursor; position cursor at snippet.cursorOffset within
        /// the inserted text.  Uses NSTextView.insertText which is tracked by the undo manager.
        func insertAtCursor(_ snippet: SnippetInsert, in textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            textView.insertText(snippet.text, replacementRange: selectedRange)
            // Move cursor to the designated offset within the inserted text
            let newCursorPos = selectedRange.location + snippet.cursorOffset
            let clamped = min(max(newCursorPos, 0), textView.string.count)
            textView.setSelectedRange(NSRange(location: clamped, length: 0))
        }

        // MARK: - Drag & Drop

        func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            hasMediaFiles(in: sender) ? .copy : []
        }

        func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            guard let textView = textView,
                  let urls = sender.draggingPasteboard.readObjects(
                      forClasses: [NSURL.self],
                      options: [.urlReadingFileURLsOnly: true]
                  ) as? [URL] else { return false }

            // Accept anything MediaKind knows about. Preview renderer
            // chooses <img> / <video> / <audio> by extension, so the same
            // `![](path)` syntax works for every dropped kind.
            let mediaURLs = urls.filter { MediaKind.from(url: $0) != nil }
            guard !mediaURLs.isEmpty else { return false }

            let lines = mediaURLs.map { url -> String in
                let alt = url.deletingPathExtension().lastPathComponent
                return "![\(alt)](\(url.path))"
            }
            let snippet = "\n" + lines.joined(separator: "\n") + "\n"
            let dropPoint = textView.convert(sender.draggingLocation, from: nil)
            let charIndex = textView.characterIndexForInsertion(at: dropPoint)

            if charIndex <= textView.string.count {
                let idx = textView.string.index(textView.string.startIndex, offsetBy: charIndex)
                var newText = textView.string
                newText.insert(contentsOf: snippet, at: idx)
                parent.text = newText
                parent.onTextChange?()
            }
            return true
        }

        private func hasMediaFiles(in info: NSDraggingInfo) -> Bool {
            guard let urls = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL] else { return false }
            return urls.contains { MediaKind.from(url: $0) != nil }
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }

            let newText = textView.string
            lastText = newText
            parent.text = newText
            parent.onTextChange?()

            if parent.isMarkdown {
                let selectedRanges = textView.selectedRanges
                let attributed = MarkdownHighlighter.highlightMac(newText, fontSize: parent.fontSize)
                let para = makeParagraphStyle(lineSpacing: parent.lineSpacing)
                attributed.addAttribute(.paragraphStyle, value: para,
                                        range: NSRange(location: 0, length: attributed.length))
                textView.textStorage?.setAttributedString(attributed)
                textView.selectedRanges = selectedRanges
            }
        }
    }
}
#endif
