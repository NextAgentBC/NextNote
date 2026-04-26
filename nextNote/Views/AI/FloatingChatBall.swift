import SwiftUI

struct FloatingChatBall: View {
    @EnvironmentObject var appState: AppState

    @State private var messages: [ChatMessage] = []
    @State private var input: String = ""
    @State private var isStreaming = false
    @State private var streamTask: Task<Void, Never>? = nil

    var body: some View {
        if appState.showChatBall {
            expandedPanel
                .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
        } else {
            collapsedBall
                .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
        }
    }

    // MARK: - Collapsed

    private var collapsedBall: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                appState.showChatBall = true
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(.separator, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                Image(systemName: "brain")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Expanded Panel

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            Divider()
            inputBar
        }
        .frame(width: 360)
        .frame(maxHeight: 500)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }

    private var header: some View {
        HStack {
            Image(systemName: "brain")
                .foregroundStyle(.secondary)
            Text("AI Chat")
                .font(.headline)
            Spacer()
            Text(appState.aiService.currentProvider.chatModel)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    appState.showChatBall = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { msg in
                        ChatBubbleView(
                            message: msg,
                            isStreaming: isStreaming && msg.id == messages.last?.id
                        )
                        .id(msg.id)
                    }
                    // Scroll anchor at bottom
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(12)
            }
            .onChange(of: messages.last?.content) {
                withAnimation { proxy.scrollTo("bottom") }
            }
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message…", text: $input, axis: .vertical)
                .font(.system(size: 13))
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .onSubmit { sendIfReady() }
                .submitLabel(.send)

            Button {
                sendIfReady()
            } label: {
                Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!canSend && !isStreaming)
            .onTapGesture {
                if isStreaming { streamTask?.cancel() ; isStreaming = false }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Cmd+Return to send
        .background(
            Button("") { sendIfReady() }
                .keyboardShortcut(.return, modifiers: .command)
                .hidden()
        )
    }

    // MARK: - Helpers

    private var canSend: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming }

    private func sendIfReady() {
        guard canSend else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        input = ""

        messages.append(ChatMessage(role: .user, content: text))
        let placeholder = ChatMessage(role: .assistant, content: "")
        messages.append(placeholder)
        let assistantIndex = messages.count - 1
        isStreaming = true

        // Build context without the empty placeholder
        let context = Array(messages.dropLast())

        streamTask = Task { @MainActor in
            let stream = appState.aiService.chat(messages: context, stream: true)
            do {
                for try await token in stream {
                    messages[assistantIndex].content += token
                }
            } catch {
                messages[assistantIndex].content = "⚠️ \(error.localizedDescription)"
            }
            isStreaming = false
        }
    }
}
