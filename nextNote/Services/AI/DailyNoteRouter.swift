import Foundation

// Resolve (and if missing, materialize) today's daily note at
// `10_Daily/YYYY-MM-DD.md` so ⌘⇧D always opens a valid tab. Honors the user's
// `99_System/Templates/Daily_Note.md` if present; otherwise falls back to a
// minimal skeleton. Pure filesystem, no SwiftUI imports — lives in Services/.
enum DailyNoteRouter {

    struct Resolved {
        let absoluteURL: URL
        /// Vault-relative path, e.g. `10_Daily/2026-04-24.md`. Used by
        /// AppState.openVaultFile.
        let relativePath: String
        let wasCreated: Bool
    }

    enum RouteError: LocalizedError {
        case noNotesRoot
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .noNotesRoot: return "Notes root not configured yet — set it in Library setup."
            case .writeFailed(let m): return "Could not write daily note: \(m)"
            }
        }
    }

    /// Resolve today's daily note, creating it from template if missing.
    /// `date` lets callers open past or future days too (not wired into UI yet,
    /// but handy for tests + future "jump to date" surface).
    static func resolve(notesRoot: URL?, date: Date = Date()) throws -> Resolved {
        guard let notesRoot else { throw RouteError.noNotesRoot }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        df.dateFormat = "yyyy-MM-dd"
        let stamp = df.string(from: date)

        let rel = "10_Daily/\(stamp).md"
        let abs = notesRoot.appendingPathComponent(rel)

        let fm = FileManager.default
        if fm.fileExists(atPath: abs.path) {
            return Resolved(absoluteURL: abs, relativePath: rel, wasCreated: false)
        }

        try fm.createDirectory(
            at: abs.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let body = buildContent(notesRoot: notesRoot, stamp: stamp)
        do {
            try body.write(to: abs, atomically: true, encoding: .utf8)
        } catch {
            throw RouteError.writeFailed(error.localizedDescription)
        }

        return Resolved(absoluteURL: abs, relativePath: rel, wasCreated: true)
    }

    // MARK: - Content

    private static func buildContent(notesRoot: URL, stamp: String) -> String {
        let templateURL = notesRoot
            .appendingPathComponent("99_System/Templates/Daily_Note.md")

        if let raw = try? String(contentsOf: templateURL, encoding: .utf8) {
            return raw.replacingOccurrences(of: "{{YYYY-MM-DD}}", with: stamp)
        }

        // Minimal fallback — vault didn't have the preset seeded.
        return """
        ---
        type: daily
        date: \(stamp)
        ---
        # \(stamp)

        ## Priorities

        ## Log

        ## Notes
        """
    }
}
