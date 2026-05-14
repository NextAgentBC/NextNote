import SwiftUI

// One-shot AI summary of the active note. Pulls the current tab's content
// (or selection — caller can override via the seed text) and streams a
// short summary through `AIService.complete`. Modal sheet so the
// invocation doesn't compete with the editor for focus.
//
// Triggered from Workflow > "AI Summarize Note" (⌥⌘S).
struct AISummarySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Text we ask the model to summarize. Set by ContentView before
    /// presenting the sheet.
    let sourceText: String

    @State private var summary: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 400)
        .task { await summarize() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
            Text("AI Summary")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                Text(errorMessage)
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                Button("Retry") {
                    Task { await summarize() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                Text(summary.isEmpty ? "Summarizing…" : summary)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .textSelection(.enabled)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Copy") {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(summary, forType: .string)
                #endif
            }
            .disabled(summary.isEmpty || isLoading)

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @MainActor
    private func summarize() async {
        guard !sourceText.isEmpty else {
            errorMessage = "Nothing to summarize — open a note first."
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        summary = ""

        let messages: [ChatMessage] = [
            ChatMessage(role: .system, content: "You are a precise note summarizer. Output only the bullet points, no preamble."),
            ChatMessage(role: .user, content: "Summarize the following note in 3 to 5 short bullet points.\n\n\(sourceText)")
        ]

        do {
            for try await event in appState.aiService.chat(messages: messages, stream: true) {
                if case .content(let token) = event {
                    summary += token
                }
            }
            summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
