import Foundation

// Very small YAML-frontmatter reader. Only recognizes the common form
//
//   ---
//   title: My Note
//   tags: [foo, bar]
//   ---
//
// Returns the parsed title + tags. We do not try to be a full YAML parser:
// values are taken as-is up to the end of the line, with surrounding quotes
// stripped. Anything fancier (multi-line values, nested keys) is ignored.
enum FrontmatterParser {

    struct Parsed {
        let title: String?
        let tags: [String]
        let bodyStart: String.Index?  // index into the original content where the body begins
    }

    /// Parse the leading frontmatter block. Returns `nil` if the content
    /// doesn't start with the `---` fence.
    static func parse(_ content: String) -> Parsed? {
        let trimmed = content.drop(while: { $0 == "\n" || $0 == "\r" })
        guard trimmed.hasPrefix("---") else { return nil }

        // Walk lines until the closing fence.
        var lines: [Substring] = []
        var iter = trimmed.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" })
            .makeIterator()
        guard let first = iter.next(), first.trimmingCharacters(in: .whitespaces) == "---"
        else { return nil }

        while let line = iter.next() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                // End of frontmatter — compute the body-start index.
                let consumed = lines.reduce(0) { $0 + $1.count + 1 } + 4 /* "---\n" */ + 4 /* "---\n" */
                let bodyIndex = content.index(content.startIndex, offsetBy: min(consumed, content.count))
                return Parsed(
                    title: extractTitle(from: lines),
                    tags: extractTags(from: lines),
                    bodyStart: bodyIndex
                )
            }
            lines.append(line)
        }
        // No closing fence — treat as no frontmatter.
        return nil
    }

    /// Convenience — just the title, or nil. Cheap to call from openVaultFile.
    static func title(from content: String) -> String? {
        parse(content)?.title
    }

    // MARK: - Internals

    private static func extractTitle(from lines: [Substring]) -> String? {
        for line in lines {
            guard let (key, rawValue) = splitKV(line) else { continue }
            if key.lowercased() == "title" {
                let value = unquote(rawValue)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    private static func extractTags(from lines: [Substring]) -> [String] {
        for line in lines {
            guard let (key, rawValue) = splitKV(line) else { continue }
            if key.lowercased() == "tags" {
                let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    return trimmed
                        .dropFirst().dropLast()
                        .split(separator: ",")
                        .map { unquote(String($0)) }
                        .filter { !$0.isEmpty }
                }
                // Bare comma-separated form: `tags: foo, bar`
                return trimmed
                    .split(separator: ",")
                    .map { unquote(String($0)) }
                    .filter { !$0.isEmpty }
            }
        }
        return []
    }

    private static func splitKV(_ line: Substring) -> (String, String)? {
        guard let sep = line.firstIndex(of: ":") else { return nil }
        let key = line[..<sep].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: sep)...].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        return (key, value)
    }

    private static func unquote(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'")),
           value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }
}
