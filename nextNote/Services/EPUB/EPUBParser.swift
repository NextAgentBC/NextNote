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
            let href = (try? item.attr("href")) ?? ""
            let mediaType = (try? item.attr("media-type")) ?? ""
            let props = (try? item.attr("properties")) ?? ""
            guard !id.isEmpty, !href.isEmpty else { continue }
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
        contentBase: URL
    ) -> [EPUBTOCNode] {
        // EPUB3: manifest item with properties="nav"
        if let navItem = manifest.values.first(where: {
            ($0.properties ?? "").contains("nav")
        }) {
            let navURL = contentBase.appendingPathComponent(navItem.href)
            if let nodes = parseNavXHTML(at: navURL), !nodes.isEmpty {
                return nodes
            }
        }

        // EPUB2: spine[toc] references an NCX manifest item
        if let tocID = try? opf.select("spine").first()?.attr("toc"),
           !tocID.isEmpty,
           let ncxItem = manifest[tocID] {
            let ncxURL = contentBase.appendingPathComponent(ncxItem.href)
            if let nodes = parseNCX(at: ncxURL), !nodes.isEmpty {
                return nodes
            }
        }

        return []
    }

    private static func parseNavXHTML(at url: URL) -> [EPUBTOCNode]? {
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
        return parseNavList(list)
    }

    private static func parseNavList(_ list: Element) -> [EPUBTOCNode] {
        var result: [EPUBTOCNode] = []
        let items = (try? list.children()) ?? Elements()
        for li in items.array() where li.tagName() == "li" {
            guard let a = try? li.select("a, span").first() else { continue }
            let title = (try? a.text()) ?? ""
            let href = (try? a.attr("href")) ?? ""
            var children: [EPUBTOCNode] = []
            if let sub = try? li.select("> ol, > ul").first() {
                children = parseNavList(sub)
            }
            result.append(EPUBTOCNode(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                href: href,
                children: children
            ))
        }
        return result
    }

    private static func parseNCX(at url: URL) -> [EPUBTOCNode]? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              let doc = try? SwiftSoup.parse(text, "", Parser.xmlParser())
        else { return nil }
        guard let navMap = try? doc.select("navMap").first() else { return nil }
        return parseNCXPoints(in: navMap)
    }

    private static func parseNCXPoints(in parent: Element) -> [EPUBTOCNode] {
        var result: [EPUBTOCNode] = []
        let points = (try? parent.children()) ?? Elements()
        for p in points.array() where p.tagName() == "navPoint" {
            let title = (try? p.select("navLabel > text").first()?.text()) ?? ""
            let href = (try? p.select("content").first()?.attr("src")) ?? ""
            let children = parseNCXPoints(in: p)
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
