import Foundation
import SwiftSoup
import ZIPFoundation

enum EPUBParseError: LocalizedError {
    case cannotUnzip(String)
    case containerMissing
    case opfMissing
    case opfMalformed(String)
    case emptySpine

    var errorDescription: String? {
        switch self {
        case .cannotUnzip(let msg):    return "Could not unzip EPUB: \(msg)"
        case .containerMissing:        return "EPUB has no META-INF/container.xml"
        case .opfMissing:              return "EPUB package OPF not found"
        case .opfMalformed(let msg):   return "EPUB OPF malformed: \(msg)"
        case .emptySpine:              return "EPUB spine is empty"
        }
    }
}

struct EPUBMetadata {
    var title: String
    var author: String?
    var publisher: String?
    var language: String?
    var coverManifestID: String?
}

struct EPUBManifestItem {
    var id: String
    var href: String
    var mediaType: String
    var properties: String?
}

struct EPUBTOCNode: Codable, Hashable {
    var title: String
    var href: String
    var children: [EPUBTOCNode]
    /// Resolved at parse time: spine index this entry points to, or nil
    /// when the TOC links to a non-spine resource.
    var spineIndex: Int?
    /// URL fragment after `#` — set when the TOC links into the middle
    /// of a chapter. nil for whole-chapter entries.
    var anchor: String?

    init(title: String, href: String, children: [EPUBTOCNode],
         spineIndex: Int? = nil, anchor: String? = nil) {
        self.title = title
        self.href = href
        self.children = children
        self.spineIndex = spineIndex
        self.anchor = anchor
    }
}

struct ParsedEPUB {
    var metadata: EPUBMetadata
    var manifest: [String: EPUBManifestItem]
    var spine: [EPUBManifestItem]
    var toc: [EPUBTOCNode]
    var unzipRoot: URL
    var opfRelativePath: String
    var contentBase: URL
    var coverAbsoluteURL: URL?
}

enum EPUBParser {

    // MARK: - Unzip

    static func unzip(epubURL: URL, to destDir: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destDir.path) {
            try fm.removeItem(at: destDir)
        }
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        do {
            try fm.unzipItem(at: epubURL, to: destDir)
        } catch {
            throw EPUBParseError.cannotUnzip(error.localizedDescription)
        }
    }

    // MARK: - Full parse

    static func parse(unzippedRoot: URL) throws -> ParsedEPUB {
        let (opfRelPath, opfText) = try readOPF(unzippedRoot: unzippedRoot)
        let contentBase = unzippedRoot.appendingPathComponent(
            (opfRelPath as NSString).deletingLastPathComponent,
            isDirectory: true
        )

        let opf = try SwiftSoup.parse(opfText, "", Parser.xmlParser())

        let metadata = try parseMetadata(opf: opf)
        let manifest = try parseManifest(opf: opf)
        let spine = try parseSpine(opf: opf, manifest: manifest)
        guard !spine.isEmpty else { throw EPUBParseError.emptySpine }

        let toc = parseTOC(
            opf: opf,
            manifest: manifest,
            spine: spine,
            contentBase: contentBase
        )

        let coverURL: URL? = {
            if let coverID = metadata.coverManifestID,
               let item = manifest[coverID] {
                return contentBase.appendingPathComponent(item.href)
            }
            // EPUB3: manifest item with properties="cover-image"
            if let item = manifest.values.first(where: {
                ($0.properties ?? "").contains("cover-image")
            }) {
                return contentBase.appendingPathComponent(item.href)
            }
            return nil
        }()

        return ParsedEPUB(
            metadata: metadata,
            manifest: manifest,
            spine: spine,
            toc: toc,
            unzipRoot: unzippedRoot,
            opfRelativePath: opfRelPath,
            contentBase: contentBase,
            coverAbsoluteURL: coverURL
        )
    }

    // MARK: - container.xml → OPF

    private static func readOPF(unzippedRoot: URL) throws -> (String, String) {
        let containerURL = unzippedRoot
            .appendingPathComponent("META-INF/container.xml")
        guard let containerData = try? Data(contentsOf: containerURL),
              let containerXML = String(data: containerData, encoding: .utf8)
        else { throw EPUBParseError.containerMissing }

        let container = try SwiftSoup.parse(containerXML, "", Parser.xmlParser())
        guard let rootfile = try container.select("rootfile").first(),
              let fullPath = try? rootfile.attr("full-path"),
              !fullPath.isEmpty
        else { throw EPUBParseError.opfMissing }

        let opfURL = unzippedRoot.appendingPathComponent(fullPath)
        guard let opfData = try? Data(contentsOf: opfURL),
              let opfText = String(data: opfData, encoding: .utf8)
        else { throw EPUBParseError.opfMissing }

        return (fullPath, opfText)
    }

    // MARK: - <metadata>

    private static func parseMetadata(opf: Document) throws -> EPUBMetadata {
        let title = firstText(opf, selectors: ["metadata > dc|title", "metadata title"]) ?? "Untitled"
        let author = firstText(opf, selectors: ["metadata > dc|creator", "metadata creator"])
        let publisher = firstText(opf, selectors: ["metadata > dc|publisher", "metadata publisher"])
        let language = firstText(opf, selectors: ["metadata > dc|language", "metadata language"])

        var coverID: String? = nil
        if let meta = try? opf.select("metadata > meta[name=cover]").first() {
            coverID = try? meta.attr("content")
        }

        return EPUBMetadata(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Untitled",
            author: author,
            publisher: publisher,
            language: language,
            coverManifestID: coverID?.nonEmpty
        )
    }

    private static func firstText(_ opf: Document, selectors: [String]) -> String? {
        for sel in selectors {
            if let el = try? opf.select(sel).first(),
               let text = try? el.text(),
               !text.isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            }
        }
        return nil
    }

    // MARK: - <manifest>

    private static func parseManifest(opf: Document) throws -> [String: EPUBManifestItem] {
        var result: [String: EPUBManifestItem] = [:]
        let items = try opf.select("manifest > item")
        for item in items.array() {
            let id = (try? item.attr("id")) ?? ""
            let rawHref = (try? item.attr("href")) ?? ""
            let mediaType = (try? item.attr("media-type")) ?? ""
            let props = (try? item.attr("properties")) ?? ""
            guard !id.isEmpty, !rawHref.isEmpty else { continue }
            // URL-decode + collapse `..` so the spine.href format the
            // sidebar matches against is independent of how the publisher
            // wrote it in the OPF (with %20, with backslashes, etc).
            let decoded = rawHref.removingPercentEncoding ?? rawHref
            let href = (decoded as NSString).standardizingPath
            result[id] = EPUBManifestItem(
                id: id,
                href: href,
                mediaType: mediaType,
                properties: props.isEmpty ? nil : props
            )
        }
        return result
    }

    // MARK: - <spine>

    private static func parseSpine(
        opf: Document,
        manifest: [String: EPUBManifestItem]
    ) throws -> [EPUBManifestItem] {
        var result: [EPUBManifestItem] = []
        let items = try opf.select("spine > itemref")
        for itemref in items.array() {
            let idref = (try? itemref.attr("idref")) ?? ""
            if let item = manifest[idref] {
                result.append(item)
            }
        }
        return result
    }

    // MARK: - TOC (nav.xhtml or toc.ncx)

    private static func parseTOC(
        opf: Document,
        manifest: [String: EPUBManifestItem],
        spine: [EPUBManifestItem],
        contentBase: URL
    ) -> [EPUBTOCNode] {
        var nodes: [EPUBTOCNode] = []

        // EPUB3: manifest item with properties="nav"
        if let navItem = manifest.values.first(where: {
            ($0.properties ?? "").contains("nav")
        }) {
            let navURL = contentBase.appendingPathComponent(navItem.href)
            if let parsed = parseNavXHTML(at: navURL, contentBase: contentBase),
               !parsed.isEmpty {
                nodes = parsed
            }
        }

        // EPUB2: spine[toc] references an NCX manifest item
        if nodes.isEmpty,
           let tocID = try? opf.select("spine").first()?.attr("toc"),
           !tocID.isEmpty,
           let ncxItem = manifest[tocID] {
            let ncxURL = contentBase.appendingPathComponent(ncxItem.href)
            if let parsed = parseNCX(at: ncxURL, contentBase: contentBase),
               !parsed.isEmpty {
                nodes = parsed
            }
        }

        // Resolve every entry's href to a spine index. URL.path equality
        // against spine[].absolute path — both sides are derived from the
        // same contentBase, so encoding / case / subdir variations are
        // already handled by URL standardization.
        let spineIndexByPath: [String: Int] = {
            var dict: [String: Int] = [:]
            for (i, item) in spine.enumerated() {
                let absURL = contentBase
                    .appendingPathComponent(item.href)
                    .standardizedFileURL
                dict[absURL.path] = i
                // Also map by lastPathComponent as a fallback for the
                // long tail where TOC and spine disagree on subdir
                // prefix.
                let last = absURL.lastPathComponent
                if dict["::file::\(last)"] == nil {
                    dict["::file::\(last)"] = i
                }
            }
            return dict
        }()

        return nodes.map { resolveSpineIndex($0, contentBase: contentBase, indexByPath: spineIndexByPath) }
    }

    private static func resolveSpineIndex(
        _ node: EPUBTOCNode,
        contentBase: URL,
        indexByPath: [String: Int]
    ) -> EPUBTOCNode {
        var copy = node

        let raw = node.href.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty && !raw.hasPrefix("#") {
            let parts = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            let path = parts.first.map(String.init) ?? raw
            let anchor = parts.count > 1 ? String(parts[1]) : ""
            if !anchor.isEmpty { copy.anchor = anchor }

            let absPath = contentBase
                .appendingPathComponent(path)
                .standardizedFileURL.path
            if let idx = indexByPath[absPath] {
                copy.spineIndex = idx
            } else {
                let last = (path as NSString).lastPathComponent
                if let idx = indexByPath["::file::\(last)"] {
                    copy.spineIndex = idx
                }
            }
        } else if raw.hasPrefix("#") {
            copy.anchor = String(raw.dropFirst())
        }

        copy.children = node.children.map {
            resolveSpineIndex($0, contentBase: contentBase, indexByPath: indexByPath)
        }
        return copy
    }

    /// Resolve a TOC href to the same form spine uses: a path relative to
    /// the OPF directory (`contentBase`). Hrefs in nav.xhtml / NCX are
    /// relative to that file's own directory, which is often a subdir
    /// (e.g. `OEBPS/Text/nav.xhtml`) — without this normalization, the
    /// sidebar's lookup against spine.href silently fails for half the
    /// EPUBs in the wild.
    static func normalizeTOCHref(_ raw: String, sourceFile: URL, contentBase: URL) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        // Anchor-only references (`#section_id`) — leave alone, the reader
        // treats these as same-chapter scrolls.
        if trimmed.hasPrefix("#") { return trimmed }

        // Strip and stash any fragment so we can rejoin after path resolution.
        let parts = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(parts[0])
        let fragment = parts.count > 1 ? "#\(parts[1])" : ""

        let decoded = rawPath.removingPercentEncoding ?? rawPath

        let sourceDir = sourceFile.deletingLastPathComponent().standardizedFileURL
        let absolute = sourceDir.appendingPathComponent(decoded).standardizedFileURL

        let basePath = contentBase.standardizedFileURL.path
        let absPath = absolute.path

        let relative: String
        if absPath.hasPrefix(basePath + "/") {
            relative = String(absPath.dropFirst(basePath.count + 1))
        } else if absPath == basePath {
            relative = ""
        } else {
            // Target is outside the OPF dir — fall back to last component
            // so at least filename-based matching still has a chance.
            relative = absolute.lastPathComponent
        }
        return relative + fragment
    }

    private static func parseNavXHTML(at url: URL, contentBase: URL) -> [EPUBTOCNode]? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              let doc = try? SwiftSoup.parse(text)
        else { return nil }
        // Prefer nav[epub:type=toc]; fall back to first nav.
        let nav: Element? = {
            if let e = try? doc.select("nav[epub:type=toc]").first() { return e }
            return try? doc.select("nav").first()
        }()
        guard let rootNav = nav,
              let list = try? rootNav.select("ol, ul").first()
        else { return nil }
        return parseNavList(list, sourceFile: url, contentBase: contentBase)
    }

    private static func parseNavList(_ list: Element, sourceFile: URL, contentBase: URL) -> [EPUBTOCNode] {
        var result: [EPUBTOCNode] = []
        let items = (try? list.children()) ?? Elements()
        for li in items.array() where li.tagName() == "li" {
            guard let a = try? li.select("a, span").first() else { continue }
            let title = (try? a.text()) ?? ""
            let rawHref = (try? a.attr("href")) ?? ""
            let href = normalizeTOCHref(rawHref, sourceFile: sourceFile, contentBase: contentBase)
            var children: [EPUBTOCNode] = []
            if let sub = try? li.select("> ol, > ul").first() {
                children = parseNavList(sub, sourceFile: sourceFile, contentBase: contentBase)
            }
            result.append(EPUBTOCNode(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                href: href,
                children: children
            ))
        }
        return result
    }

    private static func parseNCX(at url: URL, contentBase: URL) -> [EPUBTOCNode]? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              let doc = try? SwiftSoup.parse(text, "", Parser.xmlParser())
        else { return nil }
        guard let navMap = try? doc.select("navMap").first() else { return nil }
        return parseNCXPoints(in: navMap, sourceFile: url, contentBase: contentBase)
    }

    private static func parseNCXPoints(in parent: Element, sourceFile: URL, contentBase: URL) -> [EPUBTOCNode] {
        var result: [EPUBTOCNode] = []
        let points = (try? parent.children()) ?? Elements()
        for p in points.array() where p.tagName() == "navPoint" {
            let title = (try? p.select("navLabel > text").first()?.text()) ?? ""
            let rawHref = (try? p.select("content").first()?.attr("src")) ?? ""
            let href = normalizeTOCHref(rawHref, sourceFile: sourceFile, contentBase: contentBase)
            let children = parseNCXPoints(in: p, sourceFile: sourceFile, contentBase: contentBase)
            result.append(EPUBTOCNode(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                href: href,
                children: children
            ))
        }
        return result
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
