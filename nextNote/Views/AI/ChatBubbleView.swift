import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    let isStreaming: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .assistant && message.content.isEmpty && message.reasoning.isEmpty && isStreaming {
                    TypingIndicator()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.secondary.opacity(0.12), in: bubbleShape)
                } else {
                    if message.role == .assistant && !message.reasoning.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            if message.content.isEmpty && isStreaming {
                                HStack(spacing: 4) {
                                    TypingIndicator()
                                    Text("thinking…")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Text("💭 " + message.reasoning)
                                .font(.caption2)
                                .italic()
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.07), in: bubbleShape)
                    }
                    if !message.content.isEmpty {
                        Text(.init(message.content))
                            .textSelection(.enabled)
                            .font(.system(size: 13))
                            .foregroundStyle(message.role == .user ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                bubbleShape.fill(message.role == .user ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.12)))
                            )
                    }
                }
            }
            .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    private var bubbleShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14)
    }
}

private struct TypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 6, height: 6)
                    .scaleEffect(phase == i ? 1.3 : 1.0)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever().delay(0)) {
                phase = 0
            }
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { t in
                withAnimation(.easeInOut(duration: 0.4)) {
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}
