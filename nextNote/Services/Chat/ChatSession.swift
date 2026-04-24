import Foundation
import SwiftUI

/// Observable per-note chat state. Holds the message list, streaming flag,
/// and the backing vault path so persistence knows where to write.
///
/// One session is active at a time — `AppState.activeChatSession`. Switching
/// tabs swaps it out (and flushes pending saves for the outgoing one).
@MainActor
final class ChatSession: ObservableObject {
    @Published var messages: [ChatMessage]
    @Published var isStreaming: Bool = false
    @Published var streamError: String?

    /// Handle to the currently-running `ChatService.send` task so the UI can
    /// cancel it. Not published — view decides what to show based on
    /// `isStreaming`.
    var streamTask: Task<Void, Never>?

    /// Cancel the in-flight stream. The partial assistant reply stays in
    /// the transcript so the user can see what arrived before the stop.
    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        saveNow()
    }

    /// Vault-relative path this session is tied to. Immutable once created —
    /// rename/delete operate on the store, not the live session object.
    let relativePath: String

    /// Vault root URL at creation time. Used by auto-save.
    let vaultRoot: URL

    /// When sending to the LLM, truncate to this many trailing messages.
    /// The UI keeps all history visible; the context window gets the tail.
    static let contextWindow = 20

    init(relativePath: String, vaultRoot: URL, messages: [ChatMessage] = []) {
        self.relativePath = relativePath
        self.vaultRoot = vaultRoot
        self.messages = messages
    }

    /// Append a message, then persist. Call after every send / receive.
    func append(_ message: ChatMessage) {
        messages.append(message)
        saveNow()
    }

    /// Mutate the last assistant message's content in place (used during
    /// streaming — we append one empty assistant message then accumulate).
    func appendToLast(_ chunk: String) {
        guard let idx = messages.indices.last,
              messages[idx].role == .assistant else { return }
        messages[idx].content += chunk
    }

    /// Wipe all messages and the sidecar. Used by the "Clear" button.
    func clear() {
        messages.removeAll()
        ChatStore.delete(relativePath: relativePath, vaultRoot: vaultRoot)
    }

    /// Synchronous save. Cheap enough — transcripts are kilobytes and
    /// JSON encode is fast; running off-main would add a race with the next
    /// token append.
    func saveNow() {
        let transcript = ChatTranscript(
            relativePath: relativePath,
            messages: messages,
            updatedAt: Date()
        )
        try? ChatStore.save(transcript, vaultRoot: vaultRoot)
    }

    /// Tail of history for the LLM context window. UI reads `messages`
    /// directly; this is only for request building.
    var contextTail: [ChatMessage] {
        guard messages.count > Self.contextWindow else { return messages }
        return Array(messages.suffix(Self.contextWindow))
    }

    var droppedMessageCount: Int {
        max(0, messages.count - Self.contextWindow)
    }
}
