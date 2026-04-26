import Foundation

// One-shot migrator from the original 0.1.x AI Soul layout (digital-prefix
// folders + 99_System) to the v0.4 friendly layout (no prefixes; agent
// scratch under .nextnote/). Idempotent — files already under new names
// are left alone; presence of either layout is detected per-folder so
// partial migrations resume cleanly.
enum VaultMigrator {

    /// Pairs are `(oldName, newRelativePath)`. Order matters when the new
    /// path is nested under another renamed dir — but in this migration none
    /// nest beyond one level.
    private static let topLevelRenames: [(String, String)] = [
        ("00_Inbox",      "Inbox"),
        ("10_Daily",      "Daily"),
        ("20_Project",    "Projects"),
        ("20_Projects",   "Projects"),     // accepts either casing of the prior preset
        ("30_Research",   "Research"),
        ("40_Wiki",       "Wiki"),
        ("50_Resources",  "Resources"),
        ("60_Canvas",     "Canvas"),
        ("70_Swipe",      "Swipe"),
        ("90_Plans",      "Plans"),
    ]

    /// Pairs of `(99_System/<sub>, .nextnote/<sub>)`. Done in two stages:
    /// first ensure `.nextnote/` exists, then move each subdir over.
    private static let systemMoves: [(String, String)] = [
        ("99_System/Soul.md",                  ".nextnote/Soul.md"),
        ("99_System/memory",                   ".nextnote/memory"),
        ("99_System/Templates",                ".nextnote/templates"),
        ("99_System/Prompts",                  ".nextnote/prompts"),
        ("99_System/.claude/skills",           ".nextnote/skills"),
        ("99_System/sources_newsletters.md",   ".nextnote/sources_newsletters.md"),
        ("99_System/sources_products.md",      ".nextnote/sources_products.md"),
        // Raw store moves into hidden agent dir so the tree walker stops
        // descending into yt-dlp transcripts on every rescan.
        ("80_Raw",                             ".nextnote/raw"),
    ]

    struct Report {
        var renamed: [String] = []     // "old → new"
        var skipped: [String] = []     // already at target
        var conflicts: [String] = []   // both paths exist with content; needs human
    }

    enum MigrationError: LocalizedError {
        case noNotesRoot
        case moveFailed(String)

        var errorDescription: String? {
            switch self {
            case .noNotesRoot: return "Notes root not configured."
            case .moveFailed(let m): return "Migration failed: \(m)"
            }
        }
    }

    @discardableResult
    static func migrate(notesRoot: URL?) throws -> Report {
        guard let root = notesRoot else { throw MigrationError.noNotesRoot }

        let fm = FileManager.default
        var report = Report()

        // Make sure `.nextnote/` exists once up front so subsequent moves
        // can settle into it without each one creating its parent.
        let nextnoteRoot = root.appendingPathComponent(".nextnote", isDirectory: true)
        if !fm.fileExists(atPath: nextnoteRoot.path) {
            try fm.createDirectory(at: nextnoteRoot, withIntermediateDirectories: true)
        }

        for (old, new) in systemMoves + topLevelRenames {
            let oldURL = root.appendingPathComponent(old)
            let newURL = root.appendingPathComponent(new)

            let oldExists = fm.fileExists(atPath: oldURL.path)
            let newExists = fm.fileExists(atPath: newURL.path)

            if !oldExists {
                continue
            }

            if newExists {
                // Both present. If the new one is empty (just a placeholder
                // from a fresh seed), the old one is canonical — replace.
                // Otherwise flag and let the human resolve.
                if isDirectoryEmpty(newURL, fm: fm) {
                    do {
                        try fm.removeItem(at: newURL)
                        try fm.moveItem(at: oldURL, to: newURL)
                        report.renamed.append("\(old) → \(new)")
                    } catch {
                        throw MigrationError.moveFailed("\(old) → \(new): \(error.localizedDescription)")
                    }
                } else {
                    report.conflicts.append("\(old) and \(new) both exist with content — leaving as-is")
                }
                continue
            }

            // Normal case: just move.
            do {
                try fm.createDirectory(
                    at: newURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fm.moveItem(at: oldURL, to: newURL)
                report.renamed.append("\(old) → \(new)")
            } catch {
                throw MigrationError.moveFailed("\(old) → \(new): \(error.localizedDescription)")
            }
        }

        // Best-effort cleanup: if 99_System/ is empty after the moves, drop it.
        let legacy = root.appendingPathComponent("99_System")
        if fm.fileExists(atPath: legacy.path), isDirectoryEmpty(legacy, fm: fm) {
            try? fm.removeItem(at: legacy)
        }

        if report.renamed.isEmpty, report.conflicts.isEmpty {
            report.skipped.append("vault already on v0.4 layout")
        }
        return report
    }

    /// True if the directory contains no entries (other than `.DS_Store`).
    private static func isDirectoryEmpty(_ url: URL, fm: FileManager) -> Bool {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        guard let entries = try? fm.contentsOfDirectory(atPath: url.path) else { return false }
        return entries.allSatisfy { $0 == ".DS_Store" || $0 == ".gitkeep" }
    }
}
