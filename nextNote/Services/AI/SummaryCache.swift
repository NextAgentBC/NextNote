import Foundation
import CryptoKit

// File-backed JSON cache for AI outputs. Stored at
// `{vault}/.nextnote/cache.json`. Follows the vault, inspectable by the
// user, survives SwiftData schema changes.
//
// Key derivation includes model + temperature + prompt template version
// so switching models or tweaking prompts correctly invalidates old hits.
actor SummaryCache {
    private let fileURL: URL
    private var entries: [String: Entry]
    private var dirty: Bool = false

    struct Entry: Codable {
        let value: String
        let createdAt: Date
    }

    init(vaultRoot: URL) {
        self.fileURL = vaultRoot
            .appending(path: ".nextnote", directoryHint: .isDirectory)
            .appending(path: "cache.json", directoryHint: .notDirectory)

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            self.entries = loaded
        } else {
            self.entries = [:]
        }
    }

    func get(_ key: String) -> String? {
        entries[key]?.value
    }

    func put(_ key: String, value: String) {
        entries[key] = Entry(value: value, createdAt: Date())
        dirty = true
    }

    func flush() {
        guard dirty else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: [.atomic])
            dirty = false
        } catch {
            // Non-fatal — next flush will retry, cache stays in memory.
        }
    }

    // Key derivation — model + temperature + promptVersion + messages hash.
    // Deliberately a static helper so callers can compute the same key
    // without holding the actor.
    static func makeKey(
        model: String,
        temperature: Float,
        promptVersion: String,
        inputs: [String]
    ) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(model.utf8))
        hasher.update(data: Data(String(temperature).utf8))
        hasher.update(data: Data(promptVersion.utf8))
        for s in inputs {
            hasher.update(data: Data(s.utf8))
            hasher.update(data: Data("\u{1F}".utf8)) // unit separator
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
