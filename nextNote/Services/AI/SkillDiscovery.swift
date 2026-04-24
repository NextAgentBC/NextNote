import Foundation

// Enumerates `99_System/.claude/skills/*/SKILL.md` in the user's vault so the
// command palette can list them. Parses the YAML frontmatter for the
// human-readable `name` + `description` fields; anything else falls back to
// folder-name heuristics.
struct DiscoveredSkill: Identifiable, Hashable {
    var id: String { slug }
    /// Folder-name slug, e.g. `start-my-day`.
    let slug: String
    /// Human name from frontmatter; falls back to slug-as-title.
    let name: String
    /// One-line summary from frontmatter `description:`; empty when missing.
    let description: String
    /// Absolute URL to the SKILL.md file, for "open definition" actions.
    let fileURL: URL
}

enum SkillDiscovery {

    /// Return every skill under `<vaultRoot>/99_System/.claude/skills/*/SKILL.md`.
    /// Sort is stable alphabetical by slug — palette does its own fuzzy scoring
    /// on top.
    static func scan(vaultRoot: URL?) -> [DiscoveredSkill] {
        guard let vaultRoot else { return [] }
        let skillsRoot = vaultRoot
            .appendingPathComponent("99_System", isDirectory: true)
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: skillsRoot.path, isDirectory: &isDir),
              isDir.boolValue else { return [] }

        guard let entries = try? fm.contentsOfDirectory(
            at: skillsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var skills: [DiscoveredSkill] = []
        for dir in entries {
            var subIsDir: ObjCBool = false
            fm.fileExists(atPath: dir.path, isDirectory: &subIsDir)
            guard subIsDir.boolValue else { continue }

            let skillFile = dir.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: skillFile.path) else { continue }

            let slug = dir.lastPathComponent
            let parsed = parseFrontmatter(at: skillFile)
            skills.append(DiscoveredSkill(
                slug: slug,
                name: parsed.name ?? humanize(slug),
                description: parsed.description ?? "",
                fileURL: skillFile
            ))
        }

        return skills.sorted { $0.slug.localizedCaseInsensitiveCompare($1.slug) == .orderedAscending }
    }

    /// Rank skills by a simple fuzzy match against `query`. Empty query →
    /// preserve original order. Score rules: exact-prefix > substring-in-name
    /// > substring-in-description.
    static func rank(_ skills: [DiscoveredSkill], query: String) -> [DiscoveredSkill] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return skills }
        return skills
            .map { (skill: $0, score: score(skill: $0, query: q)) }
            .filter { $0.score > 0 }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                return a.skill.slug < b.skill.slug
            }
            .map { $0.skill }
    }

    // MARK: - Frontmatter

    private struct Parsed {
        var name: String?
        var description: String?
    }

    private static func parseFrontmatter(at url: URL) -> Parsed {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return Parsed() }
        // Frontmatter must open on line 1 with `---`.
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return Parsed() }

        var parsed = Parsed()
        var i = 1
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                var value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                // Strip surrounding quotes if any.
                if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                switch key {
                case "name": parsed.name = value
                case "description": parsed.description = value
                default: break
                }
            }
            i += 1
        }
        return parsed
    }

    private static func humanize(_ slug: String) -> String {
        slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    private static func score(skill: DiscoveredSkill, query: String) -> Int {
        let slug = skill.slug.lowercased()
        let name = skill.name.lowercased()
        let desc = skill.description.lowercased()
        if slug == query { return 1000 }
        if slug.hasPrefix(query) { return 500 }
        if name.hasPrefix(query) { return 400 }
        if slug.contains(query) { return 300 }
        if name.contains(query) { return 200 }
        if desc.contains(query) { return 100 }
        return 0
    }
}
