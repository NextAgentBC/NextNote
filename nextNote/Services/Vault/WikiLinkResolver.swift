import Foundation

/// Resolves Obsidian-style `[[target]]` link targets to vault-relative
/// paths. The lookup is lossy by design — multiple notes can share the
/// same base name, and a target like "Project Plan" may match either
/// `Project Plan.md` or `Archive/Project Plan.md`. We prefer:
///
///   1. exact relative-path match (`folder/note.md` or `folder/note`)
///   2. exact base-name match (case-insensitive), shorter path wins
///   3. nothing → caller decides whether to surface "create new" UX
enum WikiLinkResolver {

    /// Build a flat list of leaf .md notes once per render so each
    /// `[[target]]` lookup is O(n) over notes (small for typical vaults).
    static func indexNotes(in tree: FolderNode) -> [String] {
        var out: [String] = []
        out.reserveCapacity(128)
        collect(node: tree, into: &out)
        return out
    }

    private static func collect(node: FolderNode, into out: inout [String]) {
        for child in node.children {
            if child.isDirectory {
                collect(node: child, into: &out)
            } else {
                if (child.name as NSString).pathExtension.lowercased() == "md" {
                    out.append(child.relativePath)
                }
            }
        }
    }

    /// Resolve a single target string. Strips a trailing `.md` and leading
    /// `./` so users can write either `[[Note]]` or `[[Note.md]]`. Returns
    /// the matching vault-relative path or nil.
    static func resolve(target rawTarget: String, paths: [String]) -> String? {
        var target = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.hasPrefix("./") { target = String(target.dropFirst(2)) }
        if target.hasSuffix(".md") { target = String(target.dropLast(3)) }
        guard !target.isEmpty else { return nil }
        let targetLower = target.lowercased()

        // 1. Exact relative-path hit (with .md restored).
        let exactMatch = paths.first { path in
            let withoutExt = (path as NSString).deletingPathExtension
            return withoutExt.compare(target) == .orderedSame
                || withoutExt.compare(target, options: .caseInsensitive) == .orderedSame
        }
        if let hit = exactMatch { return hit }

        // 2. Base-name match (case-insensitive). Prefer the shortest path
        // when multiple base names collide.
        let baseHits = paths.filter { path in
            let last = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            return last.lowercased() == targetLower
        }
        return baseHits.min(by: { $0.count < $1.count })
    }
}
