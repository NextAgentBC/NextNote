import Foundation
import CryptoKit

/// Persists per-note chat transcripts as JSON sidecars inside the vault.
///
/// Layout: `<vault>/.nextnote/chats/<sha256(relativePath)>.json`. The
/// `.nextnote/` directory is already in `VaultStore.skippedDirs` so it stays
/// invisible to the sidebar tree.
///
/// Keyed by SHA256 of the relative path instead of the path itself so we
/// don't have to encode `/` characters and so rename/move is just "rehash
/// and rewrite" — no directory walks.
enum ChatStore {
    /// Where chat files live inside the given vault root. Created on demand
    /// by `save(_:)` — callers don't need to mkdir themselves.
    static func chatsDirectory(vaultRoot: URL) -> URL {
        vaultRoot
            .appending(path: ".nextnote", directoryHint: .isDirectory)
            .appending(path: "chats", directoryHint: .isDirectory)
    }

    static func url(for relativePath: String, vaultRoot: URL) -> URL {
        let key = sha(relativePath)
        return chatsDirectory(vaultRoot: vaultRoot)
            .appending(path: "\(key).json", directoryHint: .notDirectory)
    }

    /// Returns a transcript or nil if no sidecar exists yet. Missing files
    /// are the 90% case (every new note starts empty) — we don't log them.
    static func load(relativePath: String, vaultRoot: URL) -> ChatTranscript? {
        let file = url(for: relativePath, vaultRoot: vaultRoot)
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ChatTranscript.self, from: data)
    }

    /// Atomic write. Creates the chats dir if missing.
    static func save(_ transcript: ChatTranscript, vaultRoot: URL) throws {
        let dir = chatsDirectory(vaultRoot: vaultRoot)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(transcript)
        let file = url(for: transcript.relativePath, vaultRoot: vaultRoot)
        try data.write(to: file, options: [.atomic])
    }

    /// Best-effort move after the backing note was renamed. Silent on
    /// "source missing" because a note may have never been chatted about.
    static func rename(from oldRelative: String, to newRelative: String, vaultRoot: URL) {
        let oldURL = url(for: oldRelative, vaultRoot: vaultRoot)
        let newURL = url(for: newRelative, vaultRoot: vaultRoot)
        let fm = FileManager.default
        guard fm.fileExists(atPath: oldURL.path) else { return }
        try? fm.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: newURL)
        try? fm.moveItem(at: oldURL, to: newURL)

        // Update the embedded relativePath field so the file is
        // self-describing (doesn't strictly matter, but helps inspection).
        if var t = load(relativePath: newRelative, vaultRoot: vaultRoot) {
            t.relativePath = newRelative
            try? save(t, vaultRoot: vaultRoot)
        }
    }

    /// Delete the sidecar. No-op if it doesn't exist.
    static func delete(relativePath: String, vaultRoot: URL) {
        let fileURL = url(for: relativePath, vaultRoot: vaultRoot)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// When a directory moves, we rehash every chat whose stored
    /// `relativePath` started with the old prefix. Scans the chats dir.
    static func renameDirectory(from oldPrefix: String, to newPrefix: String, vaultRoot: URL) {
        let dir = chatsDirectory(vaultRoot: vaultRoot)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.pathExtension == "json" {
            guard let data = try? Data(contentsOf: entry),
                  var t = try? JSONDecoder.iso.decode(ChatTranscript.self, from: data)
            else { continue }

            let rel = t.relativePath
            let needsRewrite: Bool = {
                if rel == oldPrefix { return true }
                let prefix = oldPrefix.hasSuffix("/") ? oldPrefix : oldPrefix + "/"
                return rel.hasPrefix(prefix)
            }()
            guard needsRewrite else { continue }

            let suffix = String(rel.dropFirst(oldPrefix.count))
            let updated = newPrefix + suffix
            t.relativePath = updated
            try? save(t, vaultRoot: vaultRoot)
            // Remove the file at the old hash since save() wrote to a new
            // one keyed by the new path.
            try? fm.removeItem(at: entry)
        }
    }

    /// Delete every chat sidecar whose recorded `relativePath` is inside the
    /// deleted directory. Invoked after a folder delete.
    static func deleteDirectory(prefix: String, vaultRoot: URL) {
        let dir = chatsDirectory(vaultRoot: vaultRoot)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.pathExtension == "json" {
            guard let data = try? Data(contentsOf: entry),
                  let t = try? JSONDecoder.iso.decode(ChatTranscript.self, from: data)
            else { continue }
            let rel = t.relativePath
            let inside: Bool = {
                if rel == prefix { return true }
                let p = prefix.hasSuffix("/") ? prefix : prefix + "/"
                return rel.hasPrefix(p)
            }()
            if inside { try? fm.removeItem(at: entry) }
        }
    }

    private static func sha(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
