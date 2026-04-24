import Foundation

// Copy the bundled `vault-template/` tree into the user's Notes root so the
// vault is immediately wired up for the Claude Code / Gemini CLI workflow
// described in docs/AI_PLAN.md. Idempotent for untouched files; refuses to
// overwrite files the user already modified.
enum VaultPresetSeeder {

    enum SeedError: LocalizedError {
        case bundleMissing
        case destinationIsFile(URL)
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .bundleMissing:
                return "Vault template missing from the app bundle — reinstall NextNote."
            case .destinationIsFile(let url):
                return "Target path is a file, not a folder: \(url.path)"
            case .copyFailed(let m):
                return "Preset seed failed: \(m)"
            }
        }
    }

    struct Report {
        var copied: [String] = []      // relative paths written
        var skipped: [String] = []     // paths that already existed (untouched)
        var conflicts: [String] = []   // paths that existed with different content
    }

    /// Seed `notesRoot` with the contents of the bundled vault template.
    /// Returns a report the UI can surface.
    @discardableResult
    static func seed(into notesRoot: URL) throws -> Report {
        let fm = FileManager.default

        guard let templateURL = Bundle.main.url(
            forResource: "vault-template",
            withExtension: nil
        ) else {
            throw SeedError.bundleMissing
        }

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: notesRoot.path, isDirectory: &isDir) {
            if !isDir.boolValue { throw SeedError.destinationIsFile(notesRoot) }
        } else {
            try fm.createDirectory(at: notesRoot, withIntermediateDirectories: true)
        }

        var report = Report()
        let enumerator = fm.enumerator(
            at: templateURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]   // preserves .gitkeep — those aren't hidden
        )

        guard let enumerator else {
            throw SeedError.copyFailed("could not enumerate template bundle")
        }

        let templatePath = templateURL.standardizedFileURL.path
        for case let fileURL as URL in enumerator {
            let full = fileURL.standardizedFileURL.path
            guard full.hasPrefix(templatePath) else { continue }
            var rel = String(full.dropFirst(templatePath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }

            // Skip the template's own README.md — it's meta, not vault content.
            if rel == "README.md" { continue }

            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let dst = notesRoot.appendingPathComponent(rel)

            if isDirectory {
                if !fm.fileExists(atPath: dst.path) {
                    try fm.createDirectory(at: dst, withIntermediateDirectories: true)
                }
                continue
            }

            if fm.fileExists(atPath: dst.path) {
                // User already has a file here. If it matches what we'd write, skip
                // silently; if it differs, flag as a conflict so the user can resolve.
                if filesIdentical(fileURL, dst) {
                    report.skipped.append(rel)
                } else {
                    report.conflicts.append(rel)
                }
                continue
            }

            try fm.createDirectory(
                at: dst.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            do {
                try fm.copyItem(at: fileURL, to: dst)
                report.copied.append(rel)
            } catch {
                throw SeedError.copyFailed("\(rel): \(error.localizedDescription)")
            }
        }

        return report
    }

    private static func filesIdentical(_ a: URL, _ b: URL) -> Bool {
        guard let da = try? Data(contentsOf: a),
              let db = try? Data(contentsOf: b) else { return false }
        return da == db
    }
}
