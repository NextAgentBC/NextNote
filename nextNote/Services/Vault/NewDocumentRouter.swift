import Foundation

/// Resolve the target folder for a new vault note based on current sidebar
/// selection. Files promote to their parent directory; "" means vault root.
enum NewDocumentRouter {
    static func targetFolder(forSelection sel: String, in tree: FolderNode) -> String {
        if sel.isEmpty { return "" }
        if let node = findNode(matching: sel, in: tree) {
            return node.isDirectory ? sel : (sel as NSString).deletingLastPathComponent
        }
        return ""
    }

    private static func findNode(matching path: String, in tree: FolderNode) -> FolderNode? {
        if tree.relativePath == path { return tree }
        for child in tree.children {
            if child.relativePath == path { return child }
            if let hit = findNode(matching: path, in: child) { return hit }
        }
        return nil
    }
}
