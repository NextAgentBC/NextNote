import Foundation

/// Builds the LLM request from a ChatSession + current document state, then
/// streams tokens back into the session's last assistant message.
///
/// Thin wrapper over `AITextService.currentProvider` — no business logic of
/// its own beyond prompt assembly and accumulation.
@MainActor
enum ChatService {

    /// Preset actions surfaced as buttons above the input box. Tapping a
    /// preset inserts its template into the input (caller controls that);
    /// this enum just supplies the template text.
    enum Preset: String, CaseIterable, Identifiable {
        case polish          = "Polish"
        case summarize       = "Summarize"
        case continueWriting = "Continue"
        case generateTitle   = "Title"
        case generateExcerpt = "Excerpt"
        case translate       = "Translate"
        case backlinks       = "Backlinks"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .polish:          return "wand.and.stars"
            case .summarize:       return "text.redaction"
            case .continueWriting: return "text.append"
            case .generateTitle:   return "textformat"
            case .generateExcerpt: return "text.quote"
            case .translate:       return "globe"
            case .backlinks:       return "link"
            }
        }

        var template: String {
            switch self {
            case .polish:
                return "Polish the current document. Keep meaning, improve clarity and flow. Output only the polished text."
            case .summarize:
                return "Write a 2–3 sentence summary of the current document."
            case .continueWriting:
                return "Continue writing from where the document ends, matching the existing tone. Output only the continuation."
            case .generateTitle:
                return "Suggest 5 title options for the current document. One per line. No numbering, no commentary."
            case .generateExcerpt:
                return "Write a 1–2 sentence excerpt (< 160 chars) suitable for a homepage card."
            case .translate:
                return "Translate the current document to English. Output only the translation."
            case .backlinks:
                return "Suggest a \"## 相关笔记\" section in Markdown listing relevant sibling notes from the same folder as `[[note title]]` bullets. Use only the siblings I've provided — do not invent titles."
            }
        }
    }

    /// Send the user's message. Appends it to the session, fires an empty
    /// assistant placeholder, streams tokens into that placeholder, then
    /// persists. Errors populate `streamError`.
    ///
    /// `documentBody` is the text of the active tab at send time. `siblings`
    /// is optional folder context (title + excerpt per sibling) — included
    /// in the system prompt only when the user flips the toggle.
    static func send(
        userText: String,
        session: ChatSession,
        documentBody: String,
        includeDocument: Bool,
        siblings: [SiblingContext]
    ) async {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 1. User message lands immediately so the UI updates before the
        // LLM starts responding.
        session.append(ChatMessage(role: .user, content: trimmed))

        // 2. Placeholder assistant message the stream will accumulate into.
        session.append(ChatMessage(role: .assistant, content: ""))
        session.isStreaming = true
        session.streamError = nil
        defer { session.isStreaming = false; session.saveNow() }

        // 3. Build request.
        var llmMessages: [LLMMessage] = []
        llmMessages.append(LLMMessage(.system, buildSystemPrompt(
            relativePath: session.relativePath,
            documentBody: includeDocument ? documentBody : nil,
            siblings: siblings
        )))
        for m in session.contextTail {
            switch m.role {
            case .user:      llmMessages.append(LLMMessage(.user, m.content))
            case .assistant: llmMessages.append(LLMMessage(.assistant, m.content))
            }
        }

        // 4. Stream tokens into the last assistant message.
        let provider = AITextService.shared.currentProvider
        let stream = provider.generateStream(
            messages: llmMessages,
            parameters: LLMParameters(maxTokens: 2048, temperature: 0.4)
        )

        let stripper = ThinkStripper()
        do {
            for try await chunk in stream {
                if Task.isCancelled { break }
                let visible = stripper.process(chunk)
                if !visible.isEmpty {
                    session.appendToLast(visible)
                }
            }
            if !Task.isCancelled {
                let tail = stripper.flush()
                if !tail.isEmpty { session.appendToLast(tail) }
            }

            // Strip trailing whitespace once the stream is closed.
            if let last = session.messages.indices.last,
               session.messages[last].role == .assistant {
                session.messages[last].content = session.messages[last].content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if Task.isCancelled, let last = session.messages.indices.last,
               session.messages[last].role == .assistant,
               session.messages[last].content.isEmpty {
                session.messages[last].content = "(stopped)"
            }
        } catch is CancellationError {
            // User hit Stop — leave the partial content alone.
        } catch {
            session.streamError = error.localizedDescription
            // Keep the partial content; user can see what arrived before the
            // failure.
        }
    }

    /// Returns the sibling .md files of `relativePath` that the UI can
    /// optionally feed to the LLM. Each sibling contributes a title + short
    /// excerpt (first ~200 chars). Capped at 20 siblings to bound tokens.
    static func siblings(for relativePath: String, in vault: VaultStore) -> [SiblingContext] {
        let parentPath = (relativePath as NSString).deletingLastPathComponent
        guard let parentNode = findNode(matching: parentPath, in: vault.tree) else { return [] }

        var out: [SiblingContext] = []
        for child in parentNode.children where !child.isDirectory {
            guard child.relativePath != relativePath else { continue }
            guard let url = vault.url(for: child.relativePath) else { continue }
            guard let body = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let title = (child.name as NSString).deletingPathExtension
            let excerpt = body
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
                .prefix(200)
            out.append(SiblingContext(title: title, relativePath: child.relativePath, excerpt: String(excerpt)))
            if out.count >= 20 { break }
        }
        return out
    }

    // MARK: - Prompt building

    private static func buildSystemPrompt(relativePath: String, documentBody: String?, siblings: [SiblingContext]) -> String {
        var lines: [String] = []
        lines.append("You are an in-editor AI assistant for a Markdown notes app (nextNote).")
        lines.append("Reply in the user's language. Be concise. When the user asks for rewritten text, output only the rewritten text without commentary.")
        lines.append("Current note path: `\(relativePath)`.")

        if let body = documentBody {
            lines.append("")
            lines.append("### Current document")
            lines.append("```markdown")
            lines.append(body.isEmpty ? "(empty)" : body)
            lines.append("```")
        } else {
            lines.append("The user has hidden the document context for this turn.")
        }

        if !siblings.isEmpty {
            lines.append("")
            lines.append("### Sibling notes in the same folder")
            for s in siblings {
                lines.append("- **\(s.title)** (`\(s.relativePath)`): \(s.excerpt)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func findNode(matching path: String, in tree: FolderNode) -> FolderNode? {
        if tree.relativePath == path { return tree }
        for child in tree.children {
            if child.relativePath == path { return child }
            if let hit = findNode(matching: path, in: child) { return hit }
        }
        return nil
    }
}

/// Compact representation of a folder-sibling note for prompt injection.
struct SiblingContext: Equatable {
    let title: String
    let relativePath: String
    let excerpt: String
}

/// Strips `<think>...</think>` blocks from a token stream as chunks arrive.
/// Holds a small tail buffer so opening/closing tags split across chunks are
/// still caught. Any text inside a think block is dropped; text outside is
/// yielded verbatim.
final class ThinkStripper {
    private var pending: String = ""
    private var inThink: Bool = false

    /// Longest sequence we might need to hold before deciding it's a tag.
    /// Equals `"<think>".count - 1 == 6`; we round up for safety.
    private static let holdCount = 8

    func process(_ chunk: String) -> String {
        pending += chunk
        var result = ""
        while true {
            if inThink {
                if let range = pending.range(of: "</think>") {
                    pending = String(pending[range.upperBound...])
                    inThink = false
                    continue
                }
                // Keep a tail in case "</think>" straddles the next chunk.
                if pending.count > Self.holdCount {
                    pending = String(pending.suffix(Self.holdCount))
                }
                return result
            } else {
                if let range = pending.range(of: "<think>") {
                    result += pending[..<range.lowerBound]
                    pending = String(pending[range.upperBound...])
                    inThink = true
                    continue
                }
                // Flush everything except a small tail that could be the
                // start of a "<think>" tag.
                if pending.count > Self.holdCount {
                    let cutIdx = pending.index(pending.endIndex, offsetBy: -Self.holdCount)
                    result += pending[..<cutIdx]
                    pending = String(pending[cutIdx...])
                }
                return result
            }
        }
    }

    /// Drain any text still held in the tail buffer after the stream ended.
    /// If we were inside a think block, everything remaining is dropped.
    func flush() -> String {
        defer { pending = ""; inThink = false }
        return inThink ? "" : pending
    }
}
