import SwiftUI

/// Bottom-docked ChatGPT-style panel. One conversation per note, persisted
/// to `<vault>/.nextnote/chats/<sha>.json`. Tab switches load/save the
/// matching session through ContentView.
struct AIChatPanelView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vault: VaultStore
    @ObservedObject private var aiService = AITextService.shared
    @Binding var isPresented: Bool

    var body: some View {
        Group {
            if let session = appState.activeChatSession {
                AIChatContentView(
                    session: session,
                    isPresented: $isPresented
                )
            } else {
                noSessionState
            }
        }
        .background(.regularMaterial)
    }

    private var noSessionState: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "brain")
                    .foregroundStyle(.purple)
                Text("AI Chat").font(.headline)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            Text("Open a note to start chatting.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Separate view so `@ObservedObject var session` re-renders on every
/// `session.messages` mutation — nested ObservableObjects inside AppState
/// don't propagate their changes through AppState's `objectWillChange`.
private struct AIChatContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vault: VaultStore
    @ObservedObject private var aiService = AITextService.shared
    @ObservedObject var session: ChatSession
    @Binding var isPresented: Bool

    @State private var draft: String = ""
    @State private var includeDocument: Bool = true
    @State private var includeSiblings: Bool = false
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            presetChips
            Divider()
            composer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain")
                .foregroundStyle(.purple)
            Text("AI Chat")
                .font(.headline)

            Spacer()

            if aiService.modelState != .ready {
                Label("Model not loaded", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Toggle(isOn: $includeDocument) {
                Label("Doc", systemImage: "doc.text").font(.caption)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Send current document as context")

            Toggle(isOn: $includeSiblings) {
                Label("Folder", systemImage: "folder").font(.caption)
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Also send titles + excerpts of sibling notes")

            Button(role: .destructive) {
                session.clear()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .disabled(session.messages.isEmpty)
            .help("Clear this note's chat history")

            Button { isPresented = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close AI Panel (⌘⇧I)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcript: some View {
        if session.messages.isEmpty {
            emptyTranscript
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if session.droppedMessageCount > 0 {
                            Text("Earlier \(session.droppedMessageCount) message(s) hidden from context window.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        ForEach(session.messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                        if let err = session.streamError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 8)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: session.messages.last?.id) { _, newId in
                    if let id = newId {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: session.messages.last?.content) { _, _ in
                    if let id = session.messages.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyTranscript: some View {
        VStack(spacing: 6) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("Ask anything about this note")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Presets below fill the input; edit then send.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 4) {
                Text(message.content.isEmpty && message.role == .assistant ? "…" : message.content)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(bubbleBackground(for: message.role))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: .infinity, alignment: alignment(for: message.role))

                if message.role == .assistant, !message.content.isEmpty {
                    HStack(spacing: 6) {
                        Button("Copy") { copy(message.content) }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.tertiary).font(.caption2)
                        Button("Insert") { insertAtCursor(message.content) }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.tertiary).font(.caption2)
                        Button("Replace") { replaceDocument(message.content) }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 2)
                }
            }

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private func bubbleBackground(for role: ChatMessage.Role) -> Color {
        switch role {
        case .user:      return Color.accentColor.opacity(0.18)
        case .assistant: return Color.secondary.opacity(0.12)
        }
    }

    private func alignment(for role: ChatMessage.Role) -> Alignment {
        role == .user ? .trailing : .leading
    }

    // MARK: - Presets

    private var presetChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ChatService.Preset.allCases) { preset in
                    Button {
                        draft = preset.template
                        composerFocused = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: preset.icon)
                            Text(preset.rawValue)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask anything…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...6)
                .focused($composerFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )

            if session.isStreaming {
                Button {
                    session.cancelStreaming()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Stop")
            } else {
                Button {
                    sendIfReady()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send (⌘↵)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private var canSend: Bool {
        if session.isStreaming { return false }
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendIfReady() {
        guard canSend else { return }
        let text = draft
        draft = ""

        let body = appState.activeTab?.document.content ?? ""
        let siblings: [SiblingContext] = includeSiblings
            ? ChatService.siblings(for: session.relativePath, in: vault)
            : []

        session.streamTask = Task { @MainActor [session] in
            await ChatService.send(
                userText: text,
                session: session,
                documentBody: body,
                includeDocument: includeDocument,
                siblings: siblings
            )
        }
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    private func insertAtCursor(_ text: String) {
        guard appState.activeTabIndex != nil else { return }
        appState.pendingSnippet = SnippetInsert(text: text, cursorOffset: text.count)
    }

    private func replaceDocument(_ text: String) {
        guard let index = appState.activeTabIndex else { return }
        appState.openTabs[index].document.content = text
        appState.openTabs[index].isModified = true
    }
}
