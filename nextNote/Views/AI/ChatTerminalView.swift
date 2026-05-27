import SwiftUI

/// Warp-inspired AI chat terminal. The conversation is rendered as a
/// vertical log of `ChatBlock` cards instead of a chat-bubble stream — each
/// block is addressable, replayable, and can be inserted back into the
/// active note. Lives in a standalone NSWindow (`ChatTerminalWindowController`).
///
/// Sibling files:
///   - `+Commands.swift`     — `/search` and `/meeting` slash commands.
///   - `+BlockActions.swift` — per-block context-menu handlers (copy / retry / delete).
struct ChatTerminalView: View {
    @EnvironmentObject var appState: AppState

    @State var blocks: [ChatBlock] = []
    @State private var input: String = ""
    @State var streamTask: Task<Void, Never>? = nil
    @State private var promptHistory: [String] = []
    @State private var promptHistoryIndex: Int? = nil
    /// When on, every prompt is preceded by a system message containing the
    /// title + full markdown of the currently active note tab. Lets the user
    /// ask "explain this", "rewrite the second paragraph", etc. without
    /// having to paste anything. User toggles via the paperclip chip in the
    /// header.
    @State private var attachNoteContext: Bool = true

    /// Current block being streamed into. Same as `blocks.last` while a
    /// stream is open, `nil` otherwise.
    private var streamingBlock: ChatBlock? {
        blocks.last(where: { $0.state == .streaming })
    }

    private var isStreaming: Bool { streamingBlock != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            inputBar
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                }
        }
        .frame(
            minWidth: 480, idealWidth: 920, maxWidth: .infinity,
            minHeight: 360, idealHeight: 680, maxHeight: .infinity
        )
        .background(terminalBackground)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header
    // Mirrors `TerminalContainerView.header` so the Shell pane and the AI
    // Terminal feel like the same surface — green status dot, mono path /
    // model label, eraser + close affordances, glass-on-dark background.

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 7, height: 7)

            Image(systemName: "brain")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            Text(appState.aiService.currentProvider.chatModel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let note = activeNote {
                Button {
                    attachNoteContext.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: attachNoteContext ? "paperclip" : "paperclip.badge.ellipsis")
                            .font(.system(size: 9))
                        Text(note.title.isEmpty ? "untitled" : note.title)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(attachNoteContext
                                  ? Color.accentColor.opacity(0.18)
                                  : Color.white.opacity(0.05))
                    )
                    .foregroundStyle(attachNoteContext ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(attachNoteContext
                      ? "Note attached — click to detach (\(note.content.count) chars sent as context)"
                      : "Note detached — click to attach \(note.title) as context")
            }

            Spacer()

            Button {
                clearAll()
            } label: {
                Image(systemName: "eraser.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Clear conversation")

            Button {
                #if os(macOS)
                NSApp.keyWindow?.performClose(nil)
                #endif
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close (⌘⇧K)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            ZStack {
                Color(red: 0.145, green: 0.145, blue: 0.153)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.3)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    /// Green when idle, blue while a stream is open, red on the most recent
    /// failure. Mirrors Warp's block-status indicators in a single dot.
    private var statusDotColor: Color {
        if isStreaming { return Color(red: 0.30, green: 0.60, blue: 0.95) }
        if blocks.last?.state == .failed { return Color.red.opacity(0.85) }
        return Color(red: 0.22, green: 0.82, blue: 0.42)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if blocks.isEmpty { emptyHint }
                    ForEach(blocks) { block in
                        ChatBlockRow(
                            block: block,
                            onCopy: { copyResponse(block) },
                            onCopyMarkdown: { copyMarkdown(block) },
                            onRetry: { retry(block) },
                            onInsertIntoNote: { insertIntoNote(block) },
                            onDelete: { deleteBlock(block) }
                        )
                        .id(block.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 12)
                .padding(.trailing, 12)
            }
            .onChange(of: blocks.last?.response) { withAnimation { proxy.scrollTo("bottom") } }
            .onChange(of: blocks.last?.reasoning) { withAnimation { proxy.scrollTo("bottom") } }
            .onChange(of: blocks.count) { withAnimation { proxy.scrollTo("bottom") } }
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI terminal — every prompt becomes a block.")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("⌘↩ send · Esc cancel · ↑/↓ recall · right-click block for actions")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text("/search <query> — web search via Tavily (credbroker)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text("/meeting — organize the attached note as a meeting transcript")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(">")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 4)

            TextField("ask anything…", text: $input, axis: .vertical)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .onSubmit { sendIfReady() }
                .submitLabel(.send)
                .background(historyShortcuts)

            Button {
                if isStreaming {
                    cancelStream()
                } else {
                    sendIfReady()
                }
            } label: {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(
                        Circle().fill(canSend || isStreaming ? Color.accentColor : Color.secondary.opacity(0.3))
                    )
            }
            .buttonStyle(.borderless)
            .disabled(!canSend && !isStreaming)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(headerBackground)
        // Esc cancels the active stream.
        .background(
            Button("") { if isStreaming { cancelStream() } }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
        )
    }

    /// Stash arrow-up / arrow-down recalls behind hidden buttons. SwiftUI
    /// doesn't let TextField intercept these directly, so we piggyback on
    /// `keyboardShortcut`.
    private var historyShortcuts: some View {
        ZStack {
            Button("") { recallPrevious() }
                .keyboardShortcut(.upArrow, modifiers: [])
                .hidden()
            Button("") { recallNext() }
                .keyboardShortcut(.downArrow, modifiers: [])
                .hidden()
        }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    /// Same tone as `TerminalContainerView.header`'s base layer. Keeps the
    /// Shell pane and the AI Terminal optically identical.
    private var headerBackground: Color { Color(red: 0.145, green: 0.145, blue: 0.153) }
    private var terminalBackground: Color { Color(red: 0.110, green: 0.110, blue: 0.118) }

    func contextMessages(upTo cutoff: ChatBlock? = nil) -> [ChatMessage] {
        var messages: [ChatMessage] = []
        if let note = noteContextMessage() {
            messages.append(note)
        }
        for b in blocks {
            if let cutoff, b.id == cutoff.id { break }
            messages.append(contentsOf: b.asMessagePair)
        }
        return messages
    }

    /// TextDocument for the currently visible tab, if there is one. Drives
    /// the header chip + the system-message context that gets prepended to
    /// every prompt when the chip is on.
    var activeNote: TextDocument? {
        guard let doc = appState.activeTab?.document else { return nil }
        if doc.content.isEmpty && doc.title.isEmpty { return nil }
        return doc
    }

    /// Build a system message that pins the user's currently-open note into
    /// the conversation. The model sees the full markdown so it can answer
    /// "summarize this", "rewrite the intro", "what's missing", etc.
    /// Truncated at ~24k chars to leave room for chat history within the
    /// model's context window.
    private func noteContextMessage() -> ChatMessage? {
        guard attachNoteContext, let note = activeNote else { return nil }
        let maxChars = 24_000
        var content = note.content
        var truncatedNotice = ""
        if content.count > maxChars {
            content = String(content.prefix(maxChars))
            truncatedNotice = "\n\n[note truncated — first \(maxChars) of \(note.content.count) chars]"
        }
        let title = note.title.isEmpty ? "Untitled" : note.title
        let body = """
        You are pair-editing the user's note inside nextNote. The note's
        current contents follow, between markers. Treat this as authoritative
        context — answer questions about it, rewrite passages on request,
        propose edits in fenced markdown blocks. Don't restate it back unless
        asked.

        --- NOTE: \(title) ---
        \(content)\(truncatedNotice)
        --- END NOTE ---
        """
        return ChatMessage(role: .system, content: body)
    }

    // MARK: - Actions

    private func sendIfReady() {
        guard canSend else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = ""
        promptHistory.append(text)
        promptHistoryIndex = nil

        let provider = appState.aiService.currentProvider
        var block = ChatBlock(
            prompt: text,
            model: provider.chatModel,
            provider: provider.kind.rawValue
        )
        blocks.append(block)
        let blockID = block.id

        // Build context = every prior block's user/assistant pair, then the
        // new prompt the user just typed.
        var context = contextMessages()

        // Slash commands run a tool first and inject the result as a system
        // message before the user prompt, so the LLM can answer grounded in
        // the freshly-fetched data.
        if let query = parseSearchCommand(text) {
            streamTask = Task { @MainActor in
                await runSearchTurn(query: query, blockID: blockID, baseContext: context)
            }
            return
        }
        if parseMeetingCommand(text) {
            streamTask = Task { @MainActor in
                await runMeetingTurn(extraInstruction: meetingExtraInstruction(text),
                                     blockID: blockID,
                                     baseContext: context)
            }
            return
        }

        context.append(ChatMessage(role: .user, content: text))

        streamTask = Task { @MainActor in
            let stream = appState.aiService.chat(messages: context, stream: true)
            do {
                for try await event in stream {
                    guard let idx = blocks.firstIndex(where: { $0.id == blockID }) else { return }
                    switch event {
                    case .reasoning(let token):
                        blocks[idx].reasoning += token
                    case .content(let token):
                        blocks[idx].response += token
                    }
                }
                if let idx = blocks.firstIndex(where: { $0.id == blockID }) {
                    if blocks[idx].state == .streaming {
                        blocks[idx].state = .done
                        blocks[idx].finishedAt = Date()
                    }
                }
            } catch is CancellationError {
                if let idx = blocks.firstIndex(where: { $0.id == blockID }) {
                    blocks[idx].state = .cancelled
                    blocks[idx].finishedAt = Date()
                }
            } catch {
                if let idx = blocks.firstIndex(where: { $0.id == blockID }) {
                    blocks[idx].state = .failed
                    blocks[idx].error = error.localizedDescription
                    blocks[idx].finishedAt = Date()
                }
            }
            _ = block  // silence "unused"
        }
    }

    func failBlock(_ blockID: UUID, error: Error) {
        guard let idx = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        blocks[idx].state = .failed
        blocks[idx].error = error.localizedDescription
        blocks[idx].finishedAt = Date()
    }

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        if let idx = blocks.indices.last, blocks[idx].state == .streaming {
            blocks[idx].state = .cancelled
            blocks[idx].finishedAt = Date()
        }
    }

    private func clearAll() {
        cancelStream()
        blocks.removeAll()
    }

    private func recallPrevious() {
        guard !promptHistory.isEmpty else { return }
        let idx = (promptHistoryIndex ?? promptHistory.count) - 1
        if idx < 0 { return }
        promptHistoryIndex = idx
        input = promptHistory[idx]
    }

    private func recallNext() {
        guard let idx = promptHistoryIndex else { return }
        let next = idx + 1
        if next >= promptHistory.count {
            promptHistoryIndex = nil
            input = ""
        } else {
            promptHistoryIndex = next
            input = promptHistory[next]
        }
    }
}
