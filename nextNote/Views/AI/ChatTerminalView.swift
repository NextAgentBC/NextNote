import SwiftUI

/// Warp-inspired AI chat terminal. The conversation is rendered as a
/// vertical log of `ChatBlock` cards instead of a chat-bubble stream — each
/// block is addressable, replayable, and can be inserted back into the
/// active note. Lives in a standalone NSWindow (`ChatTerminalWindowController`).
struct ChatTerminalView: View {
    @EnvironmentObject private var appState: AppState

    @State private var blocks: [ChatBlock] = []
    @State private var input: String = ""
    @State private var streamTask: Task<Void, Never>? = nil
    @State private var promptHistory: [String] = []
    @State private var promptHistoryIndex: Int? = nil

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

    private func contextMessages(upTo cutoff: ChatBlock? = nil) -> [ChatMessage] {
        var messages: [ChatMessage] = []
        for b in blocks {
            if let cutoff, b.id == cutoff.id { break }
            messages.append(contentsOf: b.asMessagePair)
        }
        return messages
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

    private func cancelStream() {
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

    // MARK: - Block actions

    private func copyResponse(_ block: ChatBlock) {
        copyToPasteboard(block.response)
    }

    private func copyMarkdown(_ block: ChatBlock) {
        copyToPasteboard(block.asMarkdown)
    }

    private func insertIntoNote(_ block: ChatBlock) {
        let snippet = block.response
        appState.pendingSnippet = SnippetInsert(text: snippet, cursorOffset: snippet.count)
    }

    private func retry(_ block: ChatBlock) {
        guard let idx = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        // Reset this block in place, then re-stream from the same prompt
        // using only the *prior* blocks as context.
        cancelStream()
        let provider = appState.aiService.currentProvider
        var fresh = ChatBlock(prompt: block.prompt, model: provider.chatModel, provider: provider.kind.rawValue)
        fresh.state = .streaming
        blocks[idx] = fresh
        // Drop everything after this block — they're stale relative to a
        // re-asked prompt.
        if idx + 1 < blocks.count {
            blocks.removeSubrange((idx + 1)..<blocks.count)
        }
        let blockID = fresh.id
        var context = contextMessages(upTo: fresh)
        context.append(ChatMessage(role: .user, content: fresh.prompt))

        streamTask = Task { @MainActor in
            let stream = appState.aiService.chat(messages: context, stream: true)
            do {
                for try await event in stream {
                    guard let i = blocks.firstIndex(where: { $0.id == blockID }) else { return }
                    switch event {
                    case .reasoning(let token): blocks[i].reasoning += token
                    case .content(let token): blocks[i].response += token
                    }
                }
                if let i = blocks.firstIndex(where: { $0.id == blockID }), blocks[i].state == .streaming {
                    blocks[i].state = .done
                    blocks[i].finishedAt = Date()
                }
            } catch is CancellationError {
                if let i = blocks.firstIndex(where: { $0.id == blockID }) {
                    blocks[i].state = .cancelled
                    blocks[i].finishedAt = Date()
                }
            } catch {
                if let i = blocks.firstIndex(where: { $0.id == blockID }) {
                    blocks[i].state = .failed
                    blocks[i].error = error.localizedDescription
                    blocks[i].finishedAt = Date()
                }
            }
        }
    }

    private func deleteBlock(_ block: ChatBlock) {
        blocks.removeAll(where: { $0.id == block.id })
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
