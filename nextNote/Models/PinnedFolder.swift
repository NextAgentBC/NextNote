import Foundation

// One external folder that the user pinned to the sidebar. Lives outside
// the Notes vault: each instance owns a security-scoped bookmark and its
// own FolderNode tree, rebuilt by PinnedFoldersStore on adoption.
struct PinnedFolder: Identifiable, Hashable {
    let id: UUID
    var name: String
    let url: URL
    var tree: FolderNode

    init(id: UUID = UUID(), name: String, url: URL, tree: FolderNode = .empty) {
        self.id = id
        self.name = name
        self.url = url
        self.tree = tree
    }
}
