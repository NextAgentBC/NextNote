import SwiftUI

/// Top-level editor view. Wraps a platform-native text editor
/// (NSTextView on macOS, UITextView on iOS) so we can keep system undo,
/// find panel, drag-drop, and IME handling — none of which SwiftUI's
/// own TextEditor exposes well enough for a markdown-first app.
///
/// Platform variants live in `MacTextEditorView.swift` and
/// `IOSTextEditorView.swift`. Font / paragraph helpers are in
/// `EditorFontResolver.swift`.
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
