import Foundation

/// One turn in a per-note chat thread. Stable `id` so SwiftUI lists don't
/// thrash on every token while streaming.
struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: Role, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

/// On-disk envelope. Kept separate from `ChatSession` (the ObservableObject)
/// so persistence stays a value type and the SwiftUI observable doesn't leak
/// into encoder land.
struct ChatTranscript: Codable {
    /// Vault-relative path at the time of writing. Informational — the
    /// filename is the authority (SHA of current path).
    var relativePath: String
    var messages: [ChatMessage]
    var updatedAt: Date
}
