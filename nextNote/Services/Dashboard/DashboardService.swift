import Foundation
import AppKit

// Orchestrates dashboard generation for a vault.
//
// Rule:
//   - Leaf folder (contains .md files but no subfolders with their own
//     _dashboard.md): prompt over the folder's notes directly.
//   - Branch folder (contains subfolders): prompt over the subfolders'
//     _dashboard.md files only. Saves tokens.
//
// Hash used in the dashboard's ai:start marker is over the concatenation
// of the inputs (note contents for leaf, child dashboard AI bodies for
// branch). Equal hash ⇒ skip regen.
@MainActor
final class DashboardService: ObservableObject {
    static let shared = DashboardService()
    private init() {}

    @Published private(set) var running: Set<String> = []
    @Published var lastError: String?

    /// ~2KB per note when we feed into the prompt — anything larger gets
    /// truncated with a marker so the model sees the shape but doesn't eat
    /// the whole context window.
    private static let perNoteBudget = 2_000

    /// Regenerate one dashboard. `folderRelativePath` is the parent of the
    /// dashboard file, "" for vault root. `dashboardRelativePath` is the
    /// path of the `_dashboard.md` itself, used for save-back.
    func regenerate(folderRelativePath: String, dashboardRelativePath: String) async {
        let key = dashboardRelativePath
        guard !running.contains(key) else { return }
        running.insert(key)
        defer { running.remove(key) }

        do {
            try await performRegen(folderRelativePath: folderRelativePath, dashboardRelativePath: dashboardRelativePath)
        } catch {
            lastError = "Regen failed for \(dashboardRelativePath): \(error.localizedDescription)"
        }
    }

    /// Walk the vault bottom-up and regenerate every _dashboard.md that
    /// has stale inputs. Used by "Rebuild All Dashboards" and by the daily
    /// digest pre-step.
    func regenerateAll() async {
        let tree = VaultStoreAccess.tree
        await walkAndRegen(node: tree)
    }

    private func walkAndRegen(node: FolderNode) async {
        // Children first (leaves before branches).
        for child in node.children where child.isDirectory {
            await walkAndRegen(node: child)
        }

        // If this folder has (or should have) a dashboard, regen it.
        let folderPath = node.relativePath
        let dashPath = folderPath.isEmpty ? "_dashboard.md" : "\(folderPath)/_dashboard.md"
        if node.isDirectory {
            let hasMdChild = node.children.contains { !$0.isDirectory && $0.name.hasSuffix(".md") }
            let hasSubfolder = node.children.contains { $0.isDirectory }
            guard hasMdChild || hasSubfolder else { return }
            await regenerate(folderRelativePath: folderPath, dashboardRelativePath: dashPath)
        }
    }

    // MARK: - Internals

    private func performRegen(folderRelativePath: String, dashboardRelativePath: String) async throws {
        guard let vaultRoot = VaultStoreAccess.rootURL else {
            throw DashboardError.noVault
        }
        guard let dashURL = VaultStoreAccess.url(for: dashboardRelativePath) else {
            throw DashboardError.noVault
        }

        // Look up the folder node in the current tree. Rescan if missing.
        guard let folderNode = Self.findNode(matchingPath: folderRelativePath, in: VaultStoreAccess.tree) else {
            throw DashboardError.folderMissing(folderRelativePath)
        }

        // Decide leaf vs branch
        let subfolders = folderNode.children.filter { $0.isDirectory }
        let isBranch = !subfolders.isEmpty

        let (inputs, combinedHash): ([(String, String)], String)
        if isBranch {
            inputs = try Self.collectChildDashboards(subfolders: subfolders, vaultRoot: vaultRoot)
            combinedHash = Self.hash(inputs)
        } else {
            let notes = folderNode.children.filter { !$0.isDirectory && $0.name.hasSuffix(".md") && $0.name != "_dashboard.md" }
            inputs = try Self.collectNotes(notes: notes, vaultRoot: vaultRoot)
            combinedHash = Self.hash(inputs)
        }

        // Load existing dashboard, short-circuit if hash matches.
        let existing = (try? NoteIO.read(url: dashURL)) ?? ""
        let parsed = DashboardDocument.parse(existing)
        if parsed.aiInputHash == combinedHash, !parsed.ai.isEmpty {
            // No change since last regen.
            return
        }

        // Build prompt
        let userPrompt: String
        if isBranch {
            userPrompt = DashboardPrompts.branchUserPrompt(
                folderName: folderRelativePath,
                childDashboards: inputs
            )
        } else {
            userPrompt = DashboardPrompts.leafUserPrompt(
                folderName: folderRelativePath,
                items: inputs
            )
        }

        let provider = AITextService.shared.currentProvider
        let ai = try await provider.generate(
            messages: [
                LLMMessage(.system, DashboardPrompts.system),
                LLMMessage(.user, userPrompt)
            ],
            parameters: LLMParameters(maxTokens: 1200, temperature: 0.3)
        )

        let newContent = DashboardDocument.serialize(
            pinned: parsed.pinned,
            ai: ai,
            aiInputHash: combinedHash
        )
        try NoteIO.write(url: dashURL, content: newContent)
    }

    // MARK: - Input collectors

    private static func collectNotes(
        notes: [FolderNode],
        vaultRoot: URL
    ) throws -> [(String, String)] {
        var out: [(String, String)] = []
        for note in notes {
            guard let url = VaultStoreAccess.url(for: note.relativePath) else { continue }
            let raw = (try? NoteIO.read(url: url)) ?? ""
            let trimmed = raw.count > perNoteBudget
                ? String(raw.prefix(perNoteBudget)) + "\n…[truncated]"
                : raw
            out.append((note.relativePath, trimmed))
        }
        return out
    }

    private static func collectChildDashboards(
        subfolders: [FolderNode],
        vaultRoot: URL
    ) throws -> [(String, String)] {
        var out: [(String, String)] = []
        for sub in subfolders {
            let dashPath = "\(sub.relativePath)/_dashboard.md"
            guard let url = VaultStoreAccess.url(for: dashPath) else { continue }
            let raw = (try? NoteIO.read(url: url)) ?? ""
            let parsed = DashboardDocument.parse(raw)
            // Prefer the AI body if present (it's the distilled form); otherwise pinned.
            let body = parsed.ai.isEmpty ? parsed.pinned : parsed.ai
            if body.isEmpty { continue }
            let trimmed = body.count > perNoteBudget
                ? String(body.prefix(perNoteBudget)) + "\n…[truncated]"
                : body
            out.append((dashPath, trimmed))
        }
        return out
    }

    private static func findNode(matchingPath path: String, in node: FolderNode) -> FolderNode? {
        if node.relativePath == path { return node }
        for c in node.children {
            if let hit = findNode(matchingPath: path, in: c) { return hit }
        }
        return nil
    }

    private static func hash(_ items: [(String, String)]) -> String {
        var joined = ""
        for (p, b) in items {
            joined += p
            joined += "\u{1F}"
            joined += b
            joined += "\u{1E}"
        }
        return NoteIO.sha256(joined)
    }
}

enum DashboardError: LocalizedError {
    case noVault
    case folderMissing(String)

    var errorDescription: String? {
        switch self {
        case .noVault: return "No vault is currently mounted."
        case .folderMissing(let p): return "Folder not found in the vault tree: \(p)"
        }
    }
}

// MARK: - VaultStore bridge
//
// DashboardService needs to reach the current VaultStore without taking
// an @EnvironmentObject (it's a singleton service, not a view). The
// bridge is set by VaultStore.adopt(url:) and cleared by forgetVault().
@MainActor
enum VaultStoreAccess {
    static private(set) weak var store: VaultStore?
    static var rootURL: URL? { store?.root }
    static var tree: FolderNode { store?.tree ?? .empty }
    static func url(for relativePath: String) -> URL? { store?.url(for: relativePath) }
    static func bind(_ store: VaultStore) { self.store = store }
}
