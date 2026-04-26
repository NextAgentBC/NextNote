#if os(iOS)
import SwiftUI
import UIKit

/// iOS-side native text editor backed by UITextView. Pairs with the
/// `Coordinator` for delegate-driven sync between SwiftUI binding and
/// the UITextView's text storage.
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
