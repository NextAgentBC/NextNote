import Foundation

// Tree node rebuilt on every vault scan. Cheap value type; not @Model.
// `relativePath` is vault-root-relative ("" = root, "projects/a.md" = leaf).
// Directories have `children`; files have empty children.
struct FolderNode: Identifiable, Hashable {
    let id: String           // same as relativePath; unique within a vault
    let relativePath: String
    let name: String
    let isDirectory: Bool
    var children: [FolderNode]

    var hasDashboard: Bool {
        guard isDirectory else { return false }
        return children.contains { $0.name == "_dashboard.md" }
    }

    var isDashboard: Bool { !isDirectory && name == "_dashboard.md" }

    /// OutlineGroup wants nil for leaves so it doesn't draw a disclosure.
    /// Directories return their children (empty array for empty folders).
    var outlineChildren: [FolderNode]? {
        isDirectory ? children : nil
    }

    static let empty = FolderNode(
        id: "",
        relativePath: "",
        name: "",
        isDirectory: true,
        children: []
    )
}
