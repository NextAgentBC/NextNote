import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

extension AssetLibraryView {
    func importURLs(_ urls: [URL]) {
        guard let root = libraryRoots.ensureAssetsRoot() else {
            importError = "Assets folder is not configured."
            return
        }
        let fm = FileManager.default
        var imported = 0
        var skipped: [String] = []

        for src in urls {
            guard let kind = MediaKind.from(url: src) else {
                skipped.append(src.lastPathComponent)
                continue
            }
            // Route into kind-matching default subfolder, unless the user
            // is currently viewing a specific folder — then land it there
            // so "what I see after drop" matches intent.
            let targetDir = resolveImportTarget(root: root, kind: kind)
            let dest = FileDestinations.unique(for: src.lastPathComponent, in: targetDir)
            do {
                try fm.copyItem(at: src, to: dest)
                imported += 1
            } catch {
                importError = "Copy failed: \(error.localizedDescription)"
                return
            }
        }

        if !skipped.isEmpty && imported == 0 {
            importError = "Unsupported file types: \(skipped.joined(separator: ", "))"
        }

        Task {
            await assetCatalog.scan(root: libraryRoots.assetsRoot)
            await MainActor.run { appState.triggerRescanLibrary = true }
        }
    }

    /// Pick the subfolder a new import lands in:
    ///   - viewing a specific folder → that folder
    ///   - otherwise → default kind bucket (images / videos / audio / other)
    func resolveImportTarget(root: URL, kind: MediaKind) -> URL {
        if let selected = folderFilter, !selected.isEmpty {
            let dir = root.appendingPathComponent(selected, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        return AssetLibraryActions.bucketDirectory(for: kind, root: root)
    }

    /// Move existing assets into a different folder. Triggered by dragging
    /// an asset cell onto a folder row in the left sidebar.
    func moveAssets(urls: [URL], to folder: String?) {
        guard let folder else { return }
        guard let root = libraryRoots.assetsRoot else { return }
        let fm = FileManager.default
        let destDir: URL
        if !folder.isEmpty {
            destDir = root.appendingPathComponent(folder, isDirectory: true)
            do {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            } catch {
                importError = "Move failed: \(error.localizedDescription)"
                return
            }
        } else {
            destDir = root
        }

        let destPath = destDir.standardizedFileURL.path
        var moved = 0
        for src in urls {
            // Only move files that actually live under our assets root
            // (dragging arbitrary URLs from Finder onto a folder row
            // shouldn't relocate arbitrary files).
            guard AssetURL.isUnder(src, root: root) else { continue }
            let sourceDirPath = src.deletingLastPathComponent().standardizedFileURL.path
            guard sourceDirPath != destPath else { continue }
            let dest = FileDestinations.unique(for: src.lastPathComponent, in: destDir)
            do {
                try fm.moveItem(at: src, to: dest)
                moved += 1
            } catch {
                importError = "Move failed: \(error.localizedDescription)"
                return
            }
        }
        if moved > 0 {
            Task { await assetCatalog.scan(root: libraryRoots.assetsRoot) }
        }
    }

    func commitNewFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        guard let root = libraryRoots.ensureAssetsRoot() else { return }
        do {
            let dir = try AssetLibraryActions.createFolder(named: name, under: root)
            folderFilter = dir.lastPathComponent
            Task { await assetCatalog.scan(root: libraryRoots.assetsRoot) }
        } catch {
            importError = "Create folder failed: \(error.localizedDescription)"
        }
    }

    func openImportPanel() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.importableTypes
        panel.prompt = "Import"
        Task {
            let resp: NSApplication.ModalResponse = await withCheckedContinuation { cont in
                if let window = NSApp.keyWindow {
                    panel.beginSheetModal(for: window) { cont.resume(returning: $0) }
                } else {
                    cont.resume(returning: panel.runModal())
                }
            }
            guard resp == .OK else { return }
            importURLs(panel.urls)
        }
        #endif
    }

    static var importableTypes: [UTType] {
        var out: [UTType] = [.image, .movie, .audio, .video, .mpeg4Movie]
        for ext in MediaKind.allExts {
            if let t = UTType(filenameExtension: ext) {
                out.append(t)
            }
        }
        return out
    }

    /// Paste image data (or file URLs) from the system clipboard into the
    /// Assets root. Handles three cases:
    ///   - File URLs (e.g. Finder copy of a file) → treated like a drop.
    ///   - Raw TIFF/PNG image data (e.g. screenshot ⌃⇧⌘4, Preview copy,
    ///     browser "Copy Image") → saved as `pasted-<timestamp>.png`.
    ///   - Anything else → no-op with a toast.
    func pasteFromClipboard() {
        #if os(macOS)
        let pb = NSPasteboard.general

        // File URLs first — same path as drop.
        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            importURLs(urls)
            return
        }

        // Raw image data.
        guard let root = libraryRoots.ensureAssetsRoot() else {
            importError = "Assets folder is not configured."
            return
        }
        guard let image = NSImage(pasteboard: pb) else {
            importError = "No image or file found on the clipboard."
            return
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            importError = "Could not convert the clipboard image to PNG."
            return
        }

        let stamp = Self.pasteTimestamp()
        let targetDir = resolveImportTarget(root: root, kind: .image)
        let dest = FileDestinations.unique(for: "pasted-\(stamp).png", in: targetDir)
        do {
            try png.write(to: dest, options: .atomic)
            Task {
                await assetCatalog.scan(root: libraryRoots.assetsRoot)
                await MainActor.run { appState.triggerRescanLibrary = true }
            }
        } catch {
            importError = "Save failed: \(error.localizedDescription)"
        }
        #endif
    }

    static func pasteTimestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        return fmt.string(from: Date())
    }

    func revealInFinder(_ asset: AssetCatalog.Asset) {
        FinderActions.reveal(asset.url)
    }

    func revealRootInFinder() {
        FinderActions.reveal(libraryRoots.assetsRoot)
    }

    func copyEmbedMarkdown(_ asset: AssetCatalog.Asset) {
        PasteboardActions.copyMarkdownEmbed(title: asset.title, path: asset.url.path)
    }

    func trash(_ asset: AssetCatalog.Asset) {
        do {
            try FileManager.default.trashItem(at: asset.url, resultingItemURL: nil)
            Task { await assetCatalog.scan(root: libraryRoots.assetsRoot) }
        } catch {
            importError = "Delete failed: \(error.localizedDescription)"
        }
        deleteTarget = nil
    }
}
