import Foundation
import Combine

/// Reverse-lookup index: for every `[[target]]` wiki-link in any .md note
/// inside the vault, record the source note(s) that link to it. Built on
/// demand (popover open) so we don't slow down vault scans or startup.
///
/// `entries[baseLowercase]` returns the list of source paths whose
/// body contains `[[Target]]` (case-insensitive on the base name).
@MainActor
final class BacklinksIndex: ObservableObject {
    @Published private(set) var entries: [String: [String]] = [:]
    @Published private(set) var isBuilding: Bool = false
    @Published private(set) var builtAt: Date?

    private var cancellables = Set<AnyCancellable>()

    /// Subscribe to the vault's tree publisher so the index quietly
    /// refreshes after edits land on disk. Debounced — VaultStore re-
    /// publishes on every save, and we don't want to re-walk hundreds
    /// of .md files on each keystroke-driven autosave.
    func wireToVault(_ vault: VaultStore) {
        cancellables.removeAll()
        let weakSelf = self
        vault.$tree
            .debounce(for: .seconds(2.5), scheduler: RunLoop.main)
            .sink { [weak vault] tree in
                guard let vault else { return }
                let paths = Self.collectMdPaths(in: tree)
                Task { @MainActor in
                    await weakSelf.rebuild(root: vault.root, mdRelativePaths: paths)
                }
            }
            .store(in: &cancellables)
    }

    nonisolated static func collectMdPaths(in node: FolderNode) -> [String] {
        var out: [String] = []
        out.reserveCapacity(128)
        walk(node, into: &out)
        return out
    }

    nonisolated private static func walk(_ node: FolderNode, into out: inout [String]) {
        for child in node.children {
            if child.isDirectory {
                walk(child, into: &out)
            } else if (child.name as NSString).pathExtension.lowercased() == "md" {
                out.append(child.relativePath)
            }
        }
    }

    nonisolated static let wikiLinkPattern = #"\[\[([^\]\|\n]+?)(?:\|[^\]\n]+?)?\]\]"#

    /// Rebuild the index from disk. Pass the vault root URL + the flat list
    /// of .md relative paths gathered from `vault.tree`. File reads happen
    /// off-MainActor; the published map flips on the actor at the end.
    func rebuild(root: URL?, mdRelativePaths: [String]) async {
        guard let root else {
            entries = [:]
            return
        }
        if isBuilding { return }
        isBuilding = true
        defer { isBuilding = false }

        let result: [String: [String]] = await Task.detached(priority: .utility) {
            var map: [String: [String]] = [:]
            guard let regex = try? NSRegularExpression(pattern: Self.wikiLinkPattern) else {
                return map
            }
            for relPath in mdRelativePaths {
                let url = root.appending(path: relPath, directoryHint: .notDirectory)
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let ns = content as NSString
                let matches = regex.matches(in: content, range: NSRange(location: 0, length: ns.length))
                for match in matches where match.range(at: 1).location != NSNotFound {
                    let raw = ns.substring(with: match.range(at: 1))
                    let target = Self.normalize(target: raw)
                    if target.isEmpty { continue }
                    map[target, default: []].append(relPath)
                }
            }
            // Sort + dedupe per target for stable UI.
            for key in map.keys {
                let unique = Array(Set(map[key] ?? []))
                map[key] = unique.sorted()
            }
            return map
        }.value

        entries = result
        builtAt = Date()
    }

    /// Lookup backlinks for the note at `relativePath`. Matches by the
    /// note's base name without extension — same logic the resolver uses
    /// when going the other direction.
    func backlinks(for relativePath: String) -> [String] {
        let base = ((relativePath as NSString).lastPathComponent as NSString)
            .deletingPathExtension
        let key = Self.normalize(target: base)
        return entries[key] ?? []
    }

    /// Lowercased, .md-stripped, ./- normalized form so links like
    /// `[[Note]]`, `[[note.md]]`, `[[./note]]` all hash to the same key.
    nonisolated static func normalize(target raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("./") { s = String(s.dropFirst(2)) }
        if s.hasSuffix(".md") { s = String(s.dropLast(3)) }
        // Use only the base name so `[[folder/Note]]` still matches a note
        // located anywhere by that name. Trade-off: ambiguous base names
        // collide; good enough for an MVP backlinks panel.
        if let slash = s.lastIndex(of: "/") {
            s = String(s[s.index(after: slash)...])
        }
        return s.lowercased()
    }
}
