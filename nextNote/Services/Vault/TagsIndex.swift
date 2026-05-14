import Foundation
import Combine

/// Global tag index — extracts inline `#tag` references and YAML
/// frontmatter `tags:` from every .md note in the vault. The map flips
/// to `[tag: [paths]]` so a Browse Tags UI can list every note carrying
/// a given tag with one O(1) lookup.
@MainActor
final class TagsIndex: ObservableObject {
    @Published private(set) var entries: [String: [String]] = [:]
    @Published private(set) var isBuilding: Bool = false
    @Published private(set) var builtAt: Date?

    private var cancellables = Set<AnyCancellable>()

    nonisolated static let inlineTagPattern = #"(?:^|\s)#([A-Za-z0-9_\-/]+)"#

    func wireToVault(_ vault: VaultStore) {
        cancellables.removeAll()
        let weakSelf = self
        vault.$tree
            .debounce(for: .seconds(2.5), scheduler: RunLoop.main)
            .sink { [weak vault] tree in
                guard let vault else { return }
                let paths = BacklinksIndex.collectMdPaths(in: tree)
                Task { @MainActor in
                    await weakSelf.rebuild(root: vault.root, mdRelativePaths: paths)
                }
            }
            .store(in: &cancellables)
    }

    func rebuild(root: URL?, mdRelativePaths: [String]) async {
        guard let root else {
            entries = [:]
            return
        }
        if isBuilding { return }
        isBuilding = true
        defer { isBuilding = false }

        let result: [String: [String]] = await Task.detached(priority: .utility) {
            var map: [String: Set<String>] = [:]
            guard let regex = try? NSRegularExpression(pattern: Self.inlineTagPattern) else {
                return [:]
            }
            for relPath in mdRelativePaths {
                let url = root.appending(path: relPath, directoryHint: .notDirectory)
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let tags = Self.extract(from: content, regex: regex)
                for tag in tags {
                    map[tag, default: []].insert(relPath)
                }
            }
            return map.mapValues { Array($0).sorted() }
        }.value

        entries = result
        builtAt = Date()
    }

    /// Tags that appear in a single note's content. Pure — safe to call
    /// from any actor; used by the active-note status bar pills.
    nonisolated static func tags(in content: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: inlineTagPattern) else { return [] }
        return Array(extract(from: content, regex: regex)).sorted()
    }

    /// Internal extractor — handles fenced code blocks (strip) +
    /// frontmatter (parse YAML tags).
    nonisolated private static func extract(
        from content: String,
        regex: NSRegularExpression
    ) -> Set<String> {
        var tags: Set<String> = []
        if let parsed = FrontmatterParser.parse(content) {
            for t in parsed.tags {
                let cleaned = t.trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty { tags.insert(cleaned) }
            }
        }
        let stripped = stripCodeFences(content)
        let ns = stripped as NSString
        let matches = regex.matches(in: stripped, range: NSRange(location: 0, length: ns.length))
        for match in matches where match.range(at: 1).location != NSNotFound {
            let tag = ns.substring(with: match.range(at: 1))
            if !tag.isEmpty { tags.insert(tag) }
        }
        return tags
    }

    /// Skip lines inside ```…``` fenced code blocks so a Swift snippet
    /// like `#available` doesn't pollute the tag map.
    nonisolated private static func stripCodeFences(_ content: String) -> String {
        var out = ""
        var inBlock = false
        for line in content.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inBlock.toggle()
                continue
            }
            if !inBlock {
                out += line + "\n"
            }
        }
        return out
    }
}
