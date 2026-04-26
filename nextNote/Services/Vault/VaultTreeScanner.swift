import Foundation

enum VaultTreeScanner {
    static let maxNodes = 10_000
    static let skippedDirs: Set<String> = [".git", "node_modules", ".nextnote"]
    static let imageExts: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff", "svg"
    ]

    /// Walk root and return the FolderNode tree plus a flag indicating truncation.
    static func buildTree(root: URL) -> (tree: FolderNode, truncated: Bool) {
        var nodeCount = 0
        let tree = scanDirectory(at: root, relativePath: "", nodeCount: &nodeCount)
        return (tree, nodeCount >= maxNodes)
    }

    private static func scanDirectory(
        at url: URL,
        relativePath: String,
        nodeCount: inout Int
    ) -> FolderNode {
        let name = url.lastPathComponent

        guard nodeCount < maxNodes else {
            return FolderNode(id: relativePath, relativePath: relativePath, name: name, isDirectory: true, children: [])
        }

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return FolderNode(id: relativePath, relativePath: relativePath, name: name, isDirectory: true, children: [])
        }

        let sorted = entries.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }

        var children: [FolderNode] = []
        for entry in sorted {
            guard nodeCount < maxNodes else { break }

            let entryName = entry.lastPathComponent
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if isDir {
                if skippedDirs.contains(entryName) { continue }
                let childRel = relativePath.isEmpty ? entryName : "\(relativePath)/\(entryName)"
                nodeCount += 1
                children.append(scanDirectory(at: entry, relativePath: childRel, nodeCount: &nodeCount))
            } else {
                let ext = entry.pathExtension.lowercased()
                guard ext == "md" || imageExts.contains(ext) else { continue }
                let childRel = relativePath.isEmpty ? entryName : "\(relativePath)/\(entryName)"
                nodeCount += 1
                children.append(FolderNode(
                    id: childRel,
                    relativePath: childRel,
                    name: entryName,
                    isDirectory: false,
                    children: []
                ))
            }
        }

        return FolderNode(id: relativePath, relativePath: relativePath, name: name, isDirectory: true, children: children)
    }
}
