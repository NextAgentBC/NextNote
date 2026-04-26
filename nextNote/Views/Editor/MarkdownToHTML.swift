import Foundation

/// Lightweight markdown → HTML converter (line-based, no full AST). Pulls
/// math spans into placeholders before parsing so KaTeX delimiters survive
/// markdown's `*`, `_`, `>` mangling, restores them at the end.
enum MarkdownToHTML {
    private static let mathOpen = "\u{E000}MATH"
    private static let mathClose = "\u{E001}"

    static func render(_ markdown: String) -> String {
        let (protected, mathStash) = stashMath(markdown)
        var html = ""
        var inCodeBlock = false
        var codeLanguage = ""
        var inTable = false
        var tableRowIndex = 0
        let lines = protected.components(separatedBy: "\n")

        for line in lines {
            // Code blocks
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCodeBlock {
                    html += "</code></pre>\n"
                    inCodeBlock = false
                    codeLanguage = ""
                } else {
                    codeLanguage = String(line.trimmingCharacters(in: .whitespaces).dropFirst(3))
                    let langAttr = codeLanguage.isEmpty ? "" : " class=\"language-\(escapeHTML(codeLanguage))\""
                    html += "<pre><code\(langAttr)>"
                    inCodeBlock = true
                }
                continue
            }
            if inCodeBlock {
                html += escapeHTML(line) + "\n"
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Table detection: line starts with |
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                let isSeparator = trimmed.replacingOccurrences(of: "|", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .allSatisfy { $0 == "-" || $0 == " " || $0 == ":" }

                if isSeparator { continue }

                if !inTable {
                    html += "<table>\n"
                    inTable = true
                    tableRowIndex = 0
                }

                let cells = trimmed
                    .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }

                let tag = tableRowIndex == 0 ? "th" : "td"
                html += "<tr>"
                for cell in cells {
                    html += "<\(tag)>\(processInline(cell))</\(tag)>"
                }
                html += "</tr>\n"
                tableRowIndex += 1
                continue
            }

            if inTable {
                html += "</table>\n"
                inTable = false
                tableRowIndex = 0
            }

            if trimmed.hasPrefix("######") {
                html += "<h6>\(processInline(String(trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces))))</h6>\n"; continue
            } else if trimmed.hasPrefix("#####") {
                html += "<h5>\(processInline(String(trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces))))</h5>\n"; continue
            } else if trimmed.hasPrefix("####") {
                html += "<h4>\(processInline(String(trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces))))</h4>\n"; continue
            } else if trimmed.hasPrefix("###") {
                html += "<h3>\(processInline(String(trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces))))</h3>\n"; continue
            } else if trimmed.hasPrefix("##") {
                html += "<h2>\(processInline(String(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))))</h2>\n"; continue
            } else if trimmed.hasPrefix("# ") {
                html += "<h1>\(processInline(String(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))))</h1>\n"; continue
            }

            if trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) && trimmed.count >= 3 {
                html += "<hr>\n"; continue
            }
            if trimmed.hasPrefix("> ") {
                html += "<blockquote>\(processInline(String(trimmed.dropFirst(2))))</blockquote>\n"; continue
            }
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                html += "<li>☑ \(processInline(String(trimmed.dropFirst(6))))</li>\n"; continue
            }
            if trimmed.hasPrefix("- [ ] ") {
                html += "<li>☐ \(processInline(String(trimmed.dropFirst(6))))</li>\n"; continue
            }
            if let match = line.range(of: #"^(\s*)([-*+])\s+"#, options: .regularExpression) {
                html += "<li>\(processInline(String(line[match.upperBound...])))</li>\n"; continue
            }
            if let match = line.range(of: #"^(\s*)\d+\.\s+"#, options: .regularExpression) {
                html += "<li>\(processInline(String(line[match.upperBound...])))</li>\n"; continue
            }
            if trimmed.isEmpty { html += "<br>\n"; continue }
            html += "<p>\(processInline(line))</p>\n"
        }

        if inCodeBlock { html += "</code></pre>\n" }
        if inTable { html += "</table>\n" }
        return unstashMath(html, mathStash)
    }

    static func processInline(_ text: String) -> String {
        var result = text

        // Extract ![alt](url) BEFORE escaping so the url/alt can be
        // shielded from HTML escaping and later turned into <img>/<video>/
        // <audio> depending on the file extension.
        result = MarkdownEmbeds.replace(in: result)

        // Links BEFORE escaping
        result = result.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^\)]+)\)"#,
            with: "%%LINK_START%%$2%%LINK_TEXT%%$1%%LINK_END%%",
            options: .regularExpression)

        result = escapeHTML(result)

        // Restore embeds + links from placeholders. The embed placeholder
        // encodes kind + src directly so the final tag depends on the file
        // extension captured earlier.
        result = MarkdownEmbeds.restore(in: result)
        result = result.replacingOccurrences(of: "%%LINK_START%%", with: "<a href=\"")
        result = result.replacingOccurrences(of: "%%LINK_TEXT%%", with: "\">")
        result = result.replacingOccurrences(of: "%%LINK_END%%", with: "</a>")

        // Bold
        result = result.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        result = result.replacingOccurrences(of: #"__(.+?)__"#, with: "<strong>$1</strong>", options: .regularExpression)
        // Italic
        result = result.replacingOccurrences(of: #"\*(.+?)\*"#, with: "<em>$1</em>", options: .regularExpression)
        result = result.replacingOccurrences(of: #"_(.+?)_"#, with: "<em>$1</em>", options: .regularExpression)
        // Strikethrough
        result = result.replacingOccurrences(of: #"~~(.+?)~~"#, with: "<del>$1</del>", options: .regularExpression)
        // Inline code
        result = result.replacingOccurrences(of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)

        return result
    }

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Math protection (KaTeX auto-render)
    //
    // Extract $$…$$ and $…$ spans into placeholder tokens before the
    // markdown pass, restore them afterwards so the HTML delivered to
    // KaTeX still has the original delimiters intact. Without this, `*`,
    // `_`, `>` inside a formula get mangled into bold/italic/quote markup.
    // Uses private-use Unicode markers so they can't collide with body text.

    private static func stashMath(_ input: String) -> (String, [String]) {
        var stash: [String] = []
        var out = ""
        let chars = Array(input)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            // Skip inline code spans — never treat `$` inside backticks as math.
            if c == "`" {
                let start = i
                var j = i + 1
                while j < chars.count && chars[j] != "`" { j += 1 }
                if j < chars.count { j += 1 }
                out.append(contentsOf: chars[start..<min(j, chars.count)])
                i = j
                continue
            }
            // $$ … $$ block math (non-greedy)
            if c == "$", i + 1 < chars.count, chars[i + 1] == "$" {
                let start = i
                var j = i + 2
                while j + 1 < chars.count && !(chars[j] == "$" && chars[j + 1] == "$") { j += 1 }
                if j + 1 < chars.count && chars[j] == "$" && chars[j + 1] == "$" {
                    let content = String(chars[start...j + 1])
                    let token = "\(mathOpen)\(stash.count)\(mathClose)"
                    stash.append(content)
                    out.append(token)
                    i = j + 2
                    continue
                }
            }
            // $ … $ inline math
            if c == "$" {
                let start = i
                // Skip escaped \$
                if i > 0, chars[i - 1] == "\\" { out.append(c); i += 1; continue }
                var j = i + 1
                // Don't treat standalone $ in text as math — require balanced
                // close on the same line, no whitespace immediately after open.
                if j < chars.count, chars[j] == " " || chars[j] == "\t" || chars[j] == "\n" {
                    out.append(c); i += 1; continue
                }
                while j < chars.count && chars[j] != "\n" && chars[j] != "$" { j += 1 }
                if j < chars.count, chars[j] == "$", j > start + 1 {
                    let content = String(chars[start...j])
                    let token = "\(mathOpen)\(stash.count)\(mathClose)"
                    stash.append(content)
                    out.append(token)
                    i = j + 1
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return (out, stash)
    }

    private static func unstashMath(_ html: String, _ stash: [String]) -> String {
        var out = html
        for (idx, raw) in stash.enumerated() {
            let token = "\(mathOpen)\(idx)\(mathClose)"
            out = out.replacingOccurrences(of: token, with: raw)
        }
        return out
    }
}
