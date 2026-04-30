import Foundation

/// One prompt + response unit in the AI chat terminal. Borrowed from
/// Warp's terminal `Block` concept (every shell command is a self-contained,
/// addressable, replayable card with state and metadata). Lets the UI
/// render the conversation as a vertical log of cards rather than a chat
/// bubble stream — easier to copy, retry, and feed back into the editor.
struct ChatBlock: Identifiable, Hashable {
    let id: UUID
    var prompt: String
    var response: String
    var reasoning: String
    var model: String
    var provider: String
    var state: ChatBlockState
    let createdAt: Date
    var finishedAt: Date?
    var error: String?

    init(
        prompt: String,
        model: String,
        provider: String
    ) {
        self.id = UUID()
        self.prompt = prompt
        self.response = ""
        self.reasoning = ""
        self.model = model
        self.provider = provider
        self.state = .streaming
        self.createdAt = Date()
        self.finishedAt = nil
        self.error = nil
    }

    /// Render this block as a `(user, assistant)` pair so the existing
    /// `AIService.chat(messages:)` API can use prior blocks as context for
    /// the next prompt.
    var asMessagePair: [ChatMessage] {
        var out: [ChatMessage] = [ChatMessage(role: .user, content: prompt)]
        if !response.isEmpty {
            out.append(ChatMessage(role: .assistant, content: response, reasoning: reasoning))
        }
        return out
    }

    /// Markdown rendering of just this block — `> prompt` quoted, then the
    /// response body. Used by Copy as Markdown / Insert into note.
    var asMarkdown: String {
        let promptQuoted = prompt
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> " + $0 }
            .joined(separator: "\n")
        var out = promptQuoted + "\n\n"
        if !reasoning.isEmpty {
            let reasoningQuoted = reasoning
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "<!-- 💭 " + $0 + " -->" }
                .joined(separator: "\n")
            out += reasoningQuoted + "\n\n"
        }
        out += response
        return out
    }

    /// Human-readable elapsed time. nil while streaming.
    var elapsedSeconds: Double? {
        guard let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(createdAt)
    }
}

enum ChatBlockState: String, Hashable {
    /// First token still pending — yet to receive any output from the LLM.
    case streaming
    /// Stream finished cleanly.
    case done
    /// User pressed Esc / clicked stop while the stream was open.
    case cancelled
    /// Stream raised an error. `block.error` carries the message.
    case failed
}
