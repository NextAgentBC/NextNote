import Foundation
import UniformTypeIdentifiers

enum FileType: String, Codable, CaseIterable, Identifiable {
    // Text
    case txt
    case md
    case csv
    case log
    case json

    // Markup / config (plain text, no syntax highlight yet)
    case yaml
    case toml
    case xml
    case html
    case css

    // Code (plain text, labelled for type indicator)
    case swift
    case python = "py"
    case javascript = "js"
    case typescript = "ts"
    case go
    case rust = "rs"
    case shell = "sh"

    // Books
    case epub

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .txt:        return "Plain Text"
        case .md:         return "Markdown"
        case .csv:        return "CSV"
        case .log:        return "Log"
        case .json:       return "JSON"
        case .yaml:       return "YAML"
        case .toml:       return "TOML"
        case .xml:        return "XML"
        case .html:       return "HTML"
        case .css:        return "CSS"
        case .swift:      return "Swift"
        case .python:     return "Python"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .go:         return "Go"
        case .rust:       return "Rust"
        case .shell:      return "Shell"
        case .epub:       return "EPUB"
        }
    }

    var fileExtension: String { rawValue }

    var utType: UTType {
        switch self {
        case .txt:        return .plainText
        case .md:         return UTType(filenameExtension: "md") ?? .plainText
        case .csv:        return .commaSeparatedText
        case .log:        return .log
        case .json:       return .json
        case .yaml:       return UTType(filenameExtension: "yaml") ?? .plainText
        case .toml:       return UTType(filenameExtension: "toml") ?? .plainText
        case .xml:        return .xml
        case .html:       return .html
        case .css:        return UTType(filenameExtension: "css") ?? .plainText
        case .swift:      return UTType(filenameExtension: "swift") ?? .sourceCode
        case .python:     return UTType(filenameExtension: "py") ?? .sourceCode
        case .javascript: return UTType(filenameExtension: "js") ?? .sourceCode
        case .typescript: return UTType(filenameExtension: "ts") ?? .sourceCode
        case .go:         return UTType(filenameExtension: "go") ?? .sourceCode
        case .rust:       return UTType(filenameExtension: "rs") ?? .sourceCode
        case .shell:      return UTType(filenameExtension: "sh") ?? .sourceCode
        case .epub:       return UTType(filenameExtension: "epub") ?? .data
        }
    }

    var iconName: String {
        switch self {
        case .txt:        return "doc.text"
        case .md:         return "doc.richtext"
        case .csv:        return "tablecells"
        case .log:        return "doc.text.magnifyingglass"
        case .json:       return "curlybraces"
        case .yaml, .toml: return "doc.badge.gearshape"
        case .xml, .html: return "chevron.left.forwardslash.chevron.right"
        case .css:        return "paintpalette"
        case .swift:      return "swift"
        case .python:     return "terminal"
        case .javascript, .typescript: return "curlybraces.square"
        case .go, .rust:  return "gearshape"
        case .shell:      return "terminal.fill"
        case .epub:       return "book"
        }
    }

    /// Whether this type uses Markdown syntax highlighting
    var isMarkdown: Bool { self == .md }

    static func from(url: URL) -> FileType {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": return .md
        case "csv":            return .csv
        case "log":            return .log
        case "json":           return .json
        case "yaml", "yml":    return .yaml
        case "toml":           return .toml
        case "xml":            return .xml
        case "html", "htm":    return .html
        case "css":            return .css
        case "swift":          return .swift
        case "py":             return .python
        case "js":             return .javascript
        case "ts":             return .typescript
        case "go":             return .go
        case "rs":             return .rust
        case "sh", "bash", "zsh": return .shell
        case "epub":           return .epub
        default:               return .txt
        }
    }

    /// All UTTypes accepted by the file open panel / document picker
    static var openableUTTypes: [UTType] {
        // Accept all known types plus a broad "source code" fallback
        var types: [UTType] = [
            .plainText, .commaSeparatedText, .log, .json, .xml, .html, .sourceCode,
        ]
        let extensions = ["md", "markdown", "yaml", "yml", "toml", "css",
                          "swift", "py", "js", "ts", "go", "rs", "sh", "bash", "zsh",
                          "txt", "log", "csv", "epub"]
        for ext in extensions {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }
}
