import SwiftUI

// Per-block context-menu actions invoked from ChatBlockRow's overflow
// menu — copy / insert-into-note / retry / delete. Each block in the
// transcript is addressable and re-runnable.
extension ChatTerminalView {
    func copyResponse(_ block: ChatBlock) {
        copyToPasteboard(block.response)
    }

    func copyMarkdown(_ block: ChatBlock) {
        copyToPasteboard(block.asMarkdown)
    }

    func insertIntoNote(_ block: ChatBlock) {
        let snippet = block.response
        appState.pendingSnippet = SnippetInsert(text: snippet, cursorOffset: snippet.count)
    }

    func retry(_ block: ChatBlock) {
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

    func deleteBlock(_ block: ChatBlock) {
        blocks.removeAll(where: { $0.id == block.id })
    }

    func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
