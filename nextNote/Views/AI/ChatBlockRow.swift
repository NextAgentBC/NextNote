import SwiftUI

/// One block card in the AI chat terminal. Shows the user prompt with a `>`
/// glyph (terminal-style), the assistant's reasoning trace (collapsible), and
/// the streamed response. Right-click for Copy / Retry / Insert / Delete.
struct ChatBlockRow: View {
    let block: ChatBlock
    var onCopy: () -> Void
    var onCopyMarkdown: () -> Void
    var onRetry: () -> Void
    var onInsertIntoNote: () -> Void
    var onDelete: () -> Void

    @State private var reasoningExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            promptLine
            if !block.reasoning.isEmpty { reasoningView }
            if !block.response.isEmpty { responseView }
            if let err = block.error { errorView(err) }
            footer
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 0.5)
        )
        .overlay(alignment: .leading) {
            statusDot
                .padding(.leading, 4)
        }
        .padding(.leading, 12)
        .contextMenu {
            Button("Copy Response") { onCopy() }
            Button("Copy as Markdown") { onCopyMarkdown() }
            Divider()
            Button("Insert Response into Note") { onInsertIntoNote() }
            Divider()
            Button("Retry") { onRetry() }
                .disabled(block.state == .streaming)
            Button(role: .destructive) { onDelete() } label: { Text("Delete Block") }
        }
    }

    // MARK: - Pieces

    private var promptLine: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(">")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
            Text(block.prompt)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color(white: 0.92))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reasoningView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                reasoningExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: reasoningExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                    Text("💭 reasoning")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            if reasoningExpanded {
                Text(block.reasoning)
                    .font(.system(size: 11, design: .monospaced))
                    .italic()
                    .foregroundStyle(Color(white: 0.6))
                    .textSelection(.enabled)
                    .padding(.leading, 14)
            }
        }
    }

    private var responseView: some View {
        // SwiftUI's single-Text markdown renderer collapses paragraphs and
        // lists onto one line and silently drops surrounding text when a
        // partial `**…**` arrives mid-stream. Render line-by-line instead,
        // applying inline markdown per line and falling back to verbatim on
        // parse failure. Block-level structure (headings / lists / code
        // fences / KaTeX) is best rendered via a WebView — that's a future
        // upgrade; for now this keeps Chinese, line breaks, and bullets
        // intact.
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(block.response.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                ChatMarkdownLine(line: String(line))
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Color(white: 0.95))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorView(_ err: String) -> some View {
        Text("⚠️ \(err)")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Color.red.opacity(0.85))
            .textSelection(.enabled)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(block.model)
                .font(.system(size: 10, design: .monospaced))
            if let secs = block.elapsedSeconds {
                Text(String(format: "%.1fs", secs))
                    .font(.system(size: 10, design: .monospaced))
            }
            if block.state == .cancelled {
                Text("cancelled")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.orange.opacity(0.8))
            }
            Spacer()
        }
        .foregroundStyle(.tertiary)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
    }

    private var statusColor: Color {
        switch block.state {
        case .streaming: return .blue
        case .done: return Color.green.opacity(0.8)
        case .cancelled: return Color.orange.opacity(0.8)
        case .failed: return .red
        }
    }

    private var borderColor: Color {
        switch block.state {
        case .streaming: return Color.accentColor.opacity(0.3)
        case .done: return Color.white.opacity(0.06)
        case .cancelled: return Color.orange.opacity(0.3)
        case .failed: return Color.red.opacity(0.4)
        }
    }
}

/// One line of an assistant response. Recognises a few common block
/// patterns (`# heading`, `- bullet`, ```` ``` `` ` fenced code, `> quote`)
/// and applies inline markdown to the rest. Keeps Chinese characters
/// intact — the previous single-Text approach silently dropped them when
/// a `**bold**` marker landed mid-line.
private struct ChatMarkdownLine: View {
    let line: String

    var body: some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Color.clear.frame(height: 6)
        } else if trimmed.hasPrefix("# ") {
            renderInline(String(trimmed.dropFirst(2)))
                .font(.system(size: 17, weight: .bold))
                .padding(.top, 4)
        } else if trimmed.hasPrefix("## ") {
            renderInline(String(trimmed.dropFirst(3)))
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 2)
        } else if trimmed.hasPrefix("### ") {
            renderInline(String(trimmed.dropFirst(4)))
                .font(.system(size: 14, weight: .semibold))
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .foregroundStyle(.secondary)
                renderInline(String(trimmed.dropFirst(2)))
            }
        } else if trimmed.hasPrefix("> ") {
            renderInline(String(trimmed.dropFirst(2)))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 2)
                }
        } else if let match = numberedListMatch(trimmed) {
            HStack(alignment: .top, spacing: 6) {
                Text("\(match.0).")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 16, alignment: .trailing)
                renderInline(match.1)
            }
        } else if trimmed.hasPrefix("```") {
            // Ignore fence markers — content between fences renders as
            // verbatim mono via the catch-all below for now.
            Color.clear.frame(height: 0)
        } else {
            renderInline(line)
        }
    }

    @ViewBuilder
    private func renderInline(_ s: String) -> some View {
        if let attr = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attr)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(s)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Match `\d+\. ` prefix → (number, rest).
    private func numberedListMatch(_ s: String) -> (Int, String)? {
        var idx = s.startIndex
        var digits = ""
        while idx < s.endIndex, s[idx].isNumber {
            digits.append(s[idx])
            idx = s.index(after: idx)
        }
        guard !digits.isEmpty,
              idx < s.endIndex,
              s[idx] == ".",
              s.index(after: idx) < s.endIndex,
              s[s.index(after: idx)] == " ",
              let n = Int(digits)
        else { return nil }
        let rest = String(s[s.index(idx, offsetBy: 2)...])
        return (n, rest)
    }
}
