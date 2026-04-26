import Foundation
import AppKit

extension MediaLibrary {
    /// Show NSOpenPanel to pick a persistent folder for ambient media.
    /// Saves a security-scoped bookmark, kicks off a recursive scan that
    /// auto-adds any audio/video it finds. Returns true if the user picked
    /// something.
    @discardableResult
    func pickAmbientFolder() async -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Pick a long-term folder for your ambient music and video library. Contents will be auto-added, and future downloads get organized under it."

        let resp = await withCheckedContinuation { (cont: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { cont.resume(returning: $0) }
            } else {
                cont.resume(returning: panel.runModal())
            }
        }
        guard resp == .OK, let url = panel.url else { return false }
        adoptAmbientFolder(url)
        markPrompted()
        await scanAmbientFolder()
        return true
    }

    func adoptAmbientFolder(_ url: URL) {
        ambientFolderScope?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else { return }
        ambientFolderScope = url
        ambientFolderURL = url
        AmbientFolderBookmark.save(url)
    }

    func restoreAmbientFolder() {
        guard let restored = AmbientFolderBookmark.restore() else { return }
        if restored.scopeStarted {
            ambientFolderScope = restored.url
        }
        ambientFolderURL = restored.url
    }

    /// Walk the ambient folder recursively, add every audio/video file not
    /// already in the library. Bookmarks are created under the folder's
    /// security scope (which we hold open from adopt/restore).
    func scanAmbientFolder() async {
        guard let root = ambientFolderURL else { return }
        _ = pruneMissing()
        let found = MediaScanner.walkForMedia(root: root)
        // addFiles does its own dedupe-by-path.
        _ = addFiles(found)
    }
}
