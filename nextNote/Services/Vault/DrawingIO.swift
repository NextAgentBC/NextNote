import Foundation

/// Atomic JSON read/write for `.nndraw` drawing notes. Mirrors `NoteIO` but
/// for the binary-ish drawing document. A missing/empty file decodes to nil
/// (treated as a blank canvas by the editor).
enum DrawingIO {
    static func load(url: URL) -> DrawingDoc? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(DrawingDoc.self, from: data)
    }

    static func save(url: URL, doc: DrawingDoc) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(doc)
        try data.write(to: url, options: [.atomic])
    }

    /// Encode a doc to a JSON string — used to seed a freshly-created file.
    static func encodeString(_ doc: DrawingDoc) throws -> String {
        let data = try JSONEncoder().encode(doc)
        return String(decoding: data, as: UTF8.self)
    }
}
