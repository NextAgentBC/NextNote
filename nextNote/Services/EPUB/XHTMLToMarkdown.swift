import Foundation
import SwiftSoup

// Minimal XHTML → Markdown converter for EPUB chapter export. Not exhaustive —
// covers the common block/inline elements books actually use. Unknown tags
// fall through to their text content.
enum XHTMLToMarkdown {

    static func convert(xhtml: String) throws -> String {
        let doc = try SwiftSoup.parse(xhtml)
        let body = try doc.select("body").first() ?? doc
        var out = ""
        walk(body, into: &out, listDepth: 0, inBlock: false)
        return collapseBlankLines(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func walk(
        _ node: Node,
        into out: inout String,
        listDepth: Int,
        inBlock: Bool
    ) {
        guard let el = node as? Element else {
            if let text = node as? TextNode {
                let t = text.text().replacingOccurrences(of: "\u{00A0}", with: " ")
                out += escapeInline(t)
            }
            return
        }

        let tag = el.tagName().lowercased()

        switch tag {
        case "h1": blockWrap(prefix: "# ",      el, &out, listDepth)
        case "h2": blockWrap(prefix: "## ",     el, &out, listDepth)
        case "h3": blockWrap(prefix: "### ",    el, &out, listDepth)
        case "h4": blockWrap(prefix: "#### ",   el, &out, listDepth)
        case "h5": blockWrap(prefix: "##### ",  el, &out, listDepth)
        case "h6": blockWrap(prefix: "###### ", el, &out, listDepth)

        case "p", "div", "section", "article":
            ensureBlankLine(&out)
            for child in el.getChildNodes() {
                walk(child, into: &out, listDepth: listDepth, inBlock: true)
            }
            out += "\n\n"

        case "br":
            out += "  \n"

        case "hr":
            ensureBlankLine(&out)
            out += "---\n\n"

        case "strong", "b":
            out += "**"
            for child in el.getChildNodes() { walk(child, into: &out, listDepth: listDepth, inBlock: inBlock) }
            out += "**"

        case "em", "i":
            out += "*"
            for child in el.getChildNodes() { walk(child, into: &out, listDepth: listDepth, inBlock: inBlock) }
            out += "*"

        case "code":
            if (el.parent()?.tagName().lowercased() == "pre") {
                for child in el.getChildNodes() { walk(child, into: &out, listDepth: listDepth, inBlock: inBlock) }
            } else {
                out += "`"
                out += (try? el.text()) ?? ""
                out += "`"
            }

        case "pre":
            ensureBlankLine(&out)
            let code = (try? el.text()) ?? ""
            out += "```\n\(code)\n```\n\n"

        case "blockquote":
            ensureBlankLine(&out)
            var inner = ""
            for child in el.getChildNodes() { walk(child, into: &inner, listDepth: listDepth, inBlock: true) }
            for line in inner.split(separator: "\n", omittingEmptySubsequences: false) {
                out += "> \(line)\n"
            }
            out += "\n"

        case "a":
            let href = (try? el.attr("href")) ?? ""
            out += "["
            for child in el.getChildNodes() { walk(child, into: &out, listDepth: listDepth, inBlock: inBlock) }
            out += "](\(href))"

        case "img":
            let src = (try? el.attr("src")) ?? ""
            let alt = (try? el.attr("alt")) ?? ""
            out += "![\(alt)](\(src))"

        case "ul":
            ensureBlankLine(&out)
            for child in el.children().array() where child.tagName().lowercased() == "li" {
                out += String(repeating: "  ", count: listDepth)
                out += "- "
                var inner = ""
                for n in child.getChildNodes() { walk(n, into: &inner, listDepth: listDepth + 1, inBlock: false) }
                out += inner.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            }
            out += "\n"

        case "ol":
            ensureBlankLine(&out)
            var i = 1
            for child in el.children().array() where child.tagName().lowercased() == "li" {
                out += String(repeating: "  ", count: listDepth)
                out += "\(i). "
                var inner = ""
                for n in child.getChildNodes() { walk(n, into: &inner, listDepth: listDepth + 1, inBlock: false) }
                out += inner.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
                i += 1
            }
            out += "\n"

        case "li":
            for child in el.getChildNodes() { walk(child, into: &out, listDepth: listDepth, inBlock: inBlock) }

        case "script", "style", "head", "meta", "link", "title":
            return

        default:
            for child in el.getChildNodes() { walk(child, into: &out, listDepth: listDepth, inBlock: inBlock) }
        }
    }

    private static func blockWrap(
        prefix: String,
        _ el: Element,
        _ out: inout String,
        _ listDepth: Int
    ) {
        ensureBlankLine(&out)
        out += prefix
        for child in el.getChildNodes() {
            walk(child, into: &out, listDepth: listDepth, inBlock: true)
        }
        out += "\n\n"
    }

    private static func ensureBlankLine(_ out: inout String) {
        if out.hasSuffix("\n\n") || out.isEmpty { return }
        if out.hasSuffix("\n") { out += "\n" } else { out += "\n\n" }
    }

    private static func escapeInline(_ s: String) -> String {
        // Light escape: only backslash the most common markdown-breakers when
        // they appear mid-text. Books rarely need aggressive escaping.
        s.replacingOccurrences(of: "*", with: "\\*")
         .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func collapseBlankLines(_ s: String) -> String {
        var result = s
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result
    }
}
