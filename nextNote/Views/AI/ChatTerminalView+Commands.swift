import SwiftUI

// Slash-command handling for the AI terminal: `/search` (Tavily web search
// via credbroker) and `/meeting` (organize the attached note into a
// structured meeting summary). Each command fetches/prepares data first,
// then runs a streaming follow-up prompt grounded in that data.
extension ChatTerminalView {

    // MARK: - /search slash command

    /// Match `/search <query>` or `/s <query>` (leading whitespace tolerated).
    /// Returns the trimmed query or nil when the input isn't a search command.
    func parseSearchCommand(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        for prefix in ["/search ", "/s "] {
            if t.hasPrefix(prefix) {
                let q = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return q.isEmpty ? nil : q
            }
        }
        return nil
    }

    /// `/search` turn: hit Tavily through credbroker, append the formatted
    /// results as the block's response (so the user can read raw hits), then
    /// fire one streaming follow-up so the model summarizes / answers using
    /// those results as system context.
    @MainActor
    func runSearchTurn(query: String, blockID: UUID, baseContext: [ChatMessage]) async {
        let provider = appState.aiService.currentProvider
        guard let broker = TavilyClient.brokerRoot(from: provider.chatBaseURL) else {
            failBlock(blockID, error: TavilyClient.TavilyError.noBrokerEndpoint)
            return
        }

        let endpoint = TavilyClient.endpointURL(broker: broker)
        if let idx = blocks.firstIndex(where: { $0.id == blockID }) {
            blocks[idx].response = "🔎 Searching `\(endpoint.absoluteString)` for **\(query)**…\n"
        }

        let results: [TavilyClient.SearchResult]
        do {
            results = try await TavilyClient.search(query: query, maxResults: 5, broker: broker)
        } catch {
            failBlock(blockID, error: error)
            return
        }

        let markdown = TavilyClient.formatAsMarkdown(query: query, results: results, endpoint: endpoint)
        if let idx = blocks.firstIndex(where: { $0.id == blockID }) {
            blocks[idx].response = markdown + "\n\n---\n\n"
        }

        // Stream a synthesized answer that grounds in the search results.
        var ctx = baseContext
        ctx.append(ChatMessage(
            role: .system,
            content: """
            The user asked for a web search via the /search command. Tavily
            returned the following results. Use them — and only them — as
            ground truth for this answer. Cite by [n] referring to result
            number. Be concise.

            \(markdown)
            """
        ))
        ctx.append(ChatMessage(role: .user, content: "Summarize and answer based on the search results above for: \(query)"))

        do {
            let stream = appState.aiService.chat(messages: ctx, stream: true)
            for try await event in stream {
                guard let idx = blocks.firstIndex(where: { $0.id == blockID }) else { return }
                switch event {
                case .reasoning(let token):
                    blocks[idx].reasoning += token
                case .content(let token):
                    blocks[idx].response += token
                }
            }
            if let idx = blocks.firstIndex(where: { $0.id == blockID }),
               blocks[idx].state == .streaming {
                blocks[idx].state = .done
                blocks[idx].finishedAt = Date()
            }
        } catch is CancellationError {
            if let idx = blocks.firstIndex(where: { $0.id == blockID }) {
                blocks[idx].state = .cancelled
                blocks[idx].finishedAt = Date()
            }
        } catch {
            failBlock(blockID, error: error)
        }
    }

    // MARK: - /meeting slash command

    /// `/meeting` (optionally with trailing extra instructions) runs an
    /// organize-this-transcript prompt against the currently attached note.
    /// Used after voice-dictating an entire meeting into a fresh note — one
    /// click turns the raw stream into a structured summary the user can
    /// insert back over the transcript.
    func parseMeetingCommand(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        return t == "/meeting" || t.hasPrefix("/meeting ") || t == "/m" || t.hasPrefix("/m ")
    }

    func meetingExtraInstruction(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        for prefix in ["/meeting ", "/m "] {
            if t.hasPrefix(prefix) {
                return String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    @MainActor
    func runMeetingTurn(extraInstruction: String, blockID: UUID, baseContext: [ChatMessage]) async {
        guard let note = activeNote, !note.content.isEmpty else {
            failBlock(blockID, error: MeetingError.noNote)
            return
        }

        if let idx = blocks.firstIndex(where: { $0.id == blockID }) {
            blocks[idx].response = "📝 Organizing meeting notes — **\(note.title.isEmpty ? "untitled" : note.title)**…\n\n"
        }

        let system = """
        You are organizing a raw meeting transcript that the user dictated by
        voice. The dictation contains run-on sentences, repeated phrases,
        filler words, and missing punctuation. Restructure it into clean
        markdown WITHOUT inventing facts. Use this section layout:

        ## Summary
        2-4 sentence overview.

        ## Decisions
        Bullet list. Each line states the decision and who made it (if known).

        ## Action Items
        Bullet list. Format: `- [ ] @owner — task (due: date if mentioned)`.
        Use `@unassigned` when the owner isn't clear.

        ## Open Questions
        Bullet list of unresolved points raised during the meeting.

        ## Key Points
        Topic-grouped bullet list of substantive content not covered above.

        Rules:
        - Quote exact phrasing for decisions / commitments when possible.
        - Preserve names, numbers, dates, and product/code identifiers verbatim.
        - Drop filler ("um", "you know", "like"). Don't translate the original language.
        - Output the markdown only — no preamble, no closing remarks.
        """

        var ctx = baseContext
        ctx.append(ChatMessage(role: .system, content: system))
        var user = """
        Organize the meeting transcript from the attached note titled "\(note.title.isEmpty ? "Untitled" : note.title)" using the structure above.
        """
        if !extraInstruction.isEmpty {
            user += "\n\nAdditional instructions from the user: \(extraInstruction)"
        }
        ctx.append(ChatMessage(role: .user, content: user))

        do {
            let stream = appState.aiService.chat(messages: ctx, stream: true)
            for try await event in stream {
                guard let idx = blocks.firstIndex(where: { $0.id == blockID }) else { return }
                switch event {
                case .reasoning(let token):
                    blocks[idx].reasoning += token
                case .content(let token):
                    blocks[idx].response += token
                }
            }
            if let idx = blocks.firstIndex(where: { $0.id == blockID }),
               blocks[idx].state == .streaming {
                blocks[idx].state = .done
                blocks[idx].finishedAt = Date()
            }
        } catch is CancellationError {
            if let idx = blocks.firstIndex(where: { $0.id == blockID }) {
                blocks[idx].state = .cancelled
                blocks[idx].finishedAt = Date()
            }
        } catch {
            failBlock(blockID, error: error)
        }
    }

    enum MeetingError: LocalizedError {
        case noNote
        var errorDescription: String? {
            switch self {
            case .noNote:
                return "Open a note with your meeting transcript first — /meeting reorganizes the currently attached note."
            }
        }
    }
}
