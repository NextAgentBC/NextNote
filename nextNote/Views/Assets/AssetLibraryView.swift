import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Full-screen asset library. Opens as a sheet from the Media menu (or
/// ⌘⇧A). Users drop media from Finder onto the grid — files are copied
/// into the configured Assets root and the catalog re-scans. Cells are
/// draggable; dropping one onto a Markdown editor inserts `![](path)`,
/// which the preview renderer turns into `<img>` / `<video>` / `<audio>`
/// automatically (see MarkdownPreviewView.embedKind).
///
/// Intentionally separate from `MediaLibraryView`, which is track-list
/// oriented (audio playback + playlists). Assets are visual scratchpad
/// material — the UI is a thumbnail grid, not a table.
struct AssetLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var libraryRoots: LibraryRoots
    @EnvironmentObject private var assetCatalog: AssetCatalog

    @State private var kindFilter: KindFilter = .all
    @State private var searchText: String = ""
    @State private var isDropTargeting: Bool = false
    @State private var importError: String?
    @State private var previewAsset: AssetCatalog.Asset?
    @State private var deleteTarget: AssetCatalog.Asset?
    /// nil → All folders. Empty string → loose files at the root (shown
    /// under "Loose"). Non-empty → that specific first-level subfolder.
    @State private var folderFilter: String? = nil
    @State private var showNewFolderAlert: Bool = false
    @State private var newFolderName: String = ""

    enum KindFilter: String, CaseIterable, Identifiable {
        case all     = "All"
        case image   = "Images"
        case video   = "Videos"
        case audio   = "Audio"
        var id: String { rawValue }
        var mediaKind: MediaKind? {
            switch self {
            case .all:   return nil
            case .image: return .image
            case .video: return .video
            case .audio: return .audio
            }
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                folderSidebar
                    .frame(width: 180)
                Divider()
                content
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") { commitNewFolder() }
        } message: {
            Text("Creates a subfolder under the Assets root.")
        }
        .task {
            _ = libraryRoots.ensureAssetsRoot()
            await assetCatalog.scan(root: libraryRoots.assetsRoot)
        }
        .onChange(of: libraryRoots.assetsRoot) { _, url in
            Task { await assetCatalog.scan(root: url) }
        }
        .alert("Import failed", isPresented: .init(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .sheet(item: $previewAsset) { asset in
            AssetPreviewSheet(asset: asset) { previewAsset = nil }
        }
        .confirmationDialog(
            "Move \"\(deleteTarget?.title ?? "")\" to Trash?",
            isPresented: .init(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { asset in
            Button("Move to Trash", role: .destructive) { trash(asset) }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        }
    }

    // MARK: - Header

    /// Two-row header — titles + actions on top, filter + search on a
    /// second row. Stops the whole thing from wrapping awkwardly when
    /// the sheet is at its minimum width.
    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Asset Library")
                    .font(.title2.bold())
                    .lineLimit(1)
                    .fixedSize()
                Text("\(filteredAssets.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button {
                    openImportPanel()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import files from disk")

                Button {
                    pasteFromClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut("v", modifiers: [.command])
                .help("Paste image from clipboard (⌘V)")

                Button {
                    revealRootInFinder()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Reveal the Assets folder in Finder")

                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 10) {
                Picker("", selection: $kindFilter) {
                    ForEach(KindFilter.allCases) { k in
                        Text(k.rawValue).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .labelsHidden()

                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(12)
    }

    // MARK: - Folder sidebar

    /// Left pane listing "All", "Loose", then one row per first-level
    /// subfolder under the Assets root. Default category folders
    /// (images / videos / audio / docs / other) always appear even
    /// when empty, so new users see the organization scheme up front.
    private var folderSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Folders")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    newFolderName = ""
                    showNewFolderAlert = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("New Folder")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    folderRow(label: "All", icon: "tray.full", value: nil)
                    folderRow(label: "Loose", icon: "square.dashed", value: "")
                    ForEach(sidebarFolderList, id: \.self) { name in
                        folderRow(
                            label: name,
                            icon: folderIcon(for: name),
                            value: name
                        )
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    /// Merge default folders with actual disk folders — always show the 5
    /// built-ins, add any user-created extras, alphabetical.
    private var sidebarFolderList: [String] {
        var set = Set(LibraryRoots.defaultAssetSubfolders)
        set.formUnion(assetCatalog.folders)
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func folderIcon(for name: String) -> String {
        switch name {
        case "images": return "photo"
        case "videos": return "film"
        case "audio":  return "waveform"
        case "docs":   return "doc.text"
        case "other":  return "shippingbox"
        default:       return "folder"
        }
    }

    @ViewBuilder
    private func folderRow(label: String, icon: String, value: String?) -> some View {
        let selected = folderFilter == value
        let count = countForSidebar(folder: value)
        Button {
            folderFilter = value
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(selected ? .white : .secondary)
                Text(label)
                    .lineLimit(1)
                    .foregroundStyle(selected ? .white : .primary)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(selected ? Color.white.opacity(0.9) : Color.secondary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? Color.accentColor : .clear)
                    .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Each folder row is a drop target — dragging an asset cell here
        // moves it into that subfolder. "All" is a filter, not a real
        // destination, so it deliberately rejects drops.
        .dropDestination(for: URL.self) { urls, _ in
            guard value != nil else { return false }
            moveAssets(urls: urls, to: value)
            return true
        }
    }

    private func countForSidebar(folder: String?) -> Int {
        switch folder {
        case .none: return assetCatalog.assets.count
        case .some(let f): return assetCatalog.assets.filter { $0.folder == f }.count
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ZStack {
            if filteredAssets.isEmpty {
                emptyState
            } else {
                grid
            }

            if isDropTargeting {
                dropHighlight
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            isDropTargeting = false
            importURLs(urls)
            return !urls.isEmpty
        } isTargeted: { active in
            isDropTargeting = active
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(filteredAssets) { asset in
                    AssetCell(asset: asset)
                        // Single-click opens preview — video cells
                        // surface the trim editor, audio plays inline,
                        // images get a full-size viewer. SwiftUI gives
                        // drag-gesture priority when the user clicks +
                        // drags, so cells stay draggable.
                        .onTapGesture { previewAsset = asset }
                        .contextMenu {
                            Button("Preview") { previewAsset = asset }
                            Button("Reveal in Finder") { revealInFinder(asset) }
                            Divider()
                            Button("Copy Markdown Embed") {
                                copyEmbedMarkdown(asset)
                            }
                            Menu("Move to") {
                                ForEach(sidebarFolderList, id: \.self) { name in
                                    Button(name) {
                                        moveAssets(urls: [asset.url], to: name)
                                    }
                                }
                                Divider()
                                Button("Root (loose)") {
                                    moveAssets(urls: [asset.url], to: "")
                                }
                            }
                            Divider()
                            Button("Move to Trash", role: .destructive) {
                                deleteTarget = asset
                            }
                        }
                        // URL is the simplest Transferable form. Works for
                        // both the editor (inserts Markdown embed) and the
                        // folder sidebar (moves the file between folders).
                        .draggable(asset.url) {
                            AssetCell(asset: asset)
                                .frame(width: 160)
                        }
                }
            }
            .padding(14)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "Drop files here" : "No matches")
                .font(.title3)
                .foregroundStyle(.secondary)
            if searchText.isEmpty {
                Text("Drag images, videos, and audio from Finder — or click Import.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.accentColor, lineWidth: 3)
            .padding(8)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    // MARK: - Derived

    private var filteredAssets: [AssetCatalog.Asset] {
        let base = assetCatalog.filtered(kind: kindFilter.mediaKind, folder: folderFilter)
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { $0.title.lowercased().contains(q) }
    }

    // MARK: - Actions

    private func importURLs(_ urls: [URL]) {
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
            let dest = uniqueDestination(for: src.lastPathComponent, in: targetDir)
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
    private func resolveImportTarget(root: URL, kind: MediaKind) -> URL {
        if let selected = folderFilter, !selected.isEmpty {
            let dir = root.appendingPathComponent(selected, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let bucket: String
        switch kind {
        case .image: bucket = "images"
        case .video: bucket = "videos"
        case .audio: bucket = "audio"
        }
        let dir = root.appendingPathComponent(bucket, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Move existing assets into a different folder. Triggered by dragging
    /// an asset cell onto a folder row in the left sidebar.
    private func moveAssets(urls: [URL], to folder: String?) {
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
            guard isAssetURL(src, under: root) else { continue }
            let sourceDirPath = src.deletingLastPathComponent().standardizedFileURL.path
            guard sourceDirPath != destPath else { continue }
            let dest = uniqueDestination(for: src.lastPathComponent, in: destDir)
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

    private func isAssetURL(_ url: URL, under root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(rootPath + "/")
    }

    private func commitNewFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        // Guard against path separators — keep new folders at the first
        // level under the assets root.
        let safe = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard let root = libraryRoots.ensureAssetsRoot() else { return }
        let dir = root.appendingPathComponent(safe, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            folderFilter = safe
            Task { await assetCatalog.scan(root: libraryRoots.assetsRoot) }
        } catch {
            importError = "Create folder failed: \(error.localizedDescription)"
        }
    }

    private func openImportPanel() {
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

    private static let importableTypes: [UTType] = {
        var out: [UTType] = [.image, .movie, .audio, .video, .mpeg4Movie]
        for ext in MediaKind.allExts {
            if let t = UTType(filenameExtension: ext) {
                out.append(t)
            }
        }
        return out
    }()

    /// Paste image data (or file URLs) from the system clipboard into the
    /// Assets root. Handles three cases:
    ///   - File URLs (e.g. Finder copy of a file) → treated like a drop.
    ///   - Raw TIFF/PNG image data (e.g. screenshot `⌃⇧⌘4`, Preview copy,
    ///     browser "Copy Image") → saved as `pasted-<timestamp>.png`.
    ///   - Anything else → no-op with a toast.
    private func pasteFromClipboard() {
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
        let dest = uniqueDestination(for: "pasted-\(stamp).png", in: targetDir)
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

    private static func pasteTimestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        return fmt.string(from: Date())
    }

    private func revealInFinder(_ asset: AssetCatalog.Asset) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([asset.url])
        #endif
    }

    private func revealRootInFinder() {
        #if os(macOS)
        if let root = libraryRoots.assetsRoot {
            NSWorkspace.shared.activateFileViewerSelecting([root])
        }
        #endif
    }

    private func copyEmbedMarkdown(_ asset: AssetCatalog.Asset) {
        #if os(macOS)
        let md = "![\(asset.title)](\(asset.url.path))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
        #endif
    }

    private func trash(_ asset: AssetCatalog.Asset) {
        do {
            try FileManager.default.trashItem(at: asset.url, resultingItemURL: nil)
            Task { await assetCatalog.scan(root: libraryRoots.assetsRoot) }
        } catch {
            importError = "Delete failed: \(error.localizedDescription)"
        }
        deleteTarget = nil
    }

    private func uniqueDestination(for filename: String, in dir: URL) -> URL {
        let fm = FileManager.default
        let url = dir.appendingPathComponent(filename)
        if !fm.fileExists(atPath: url.path) { return url }

        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        for n in 2... {
            let candidate = dir.appendingPathComponent("\(stem)-\(n).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }
}

// MARK: - Cell

private struct AssetCell: View {
    let asset: AssetCatalog.Asset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .windowBackgroundColor))
                AssetThumbnail(asset: asset)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(height: 120)
            .overlay(alignment: .topTrailing) {
                Image(systemName: asset.kind.iconName)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.black.opacity(0.55), in: Circle())
                    .padding(6)
            }

            Text(asset.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .truncationMode(.middle)

            if let size = asset.size {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Thumbnail

private struct AssetThumbnail: View {
    let asset: AssetCatalog.Asset
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .task(id: asset.url) {
            // Reset when the cell is reused for a different asset (shouldn't
            // happen with Identifiable + url-id but cheap insurance).
            image = nil
            image = await Self.thumbnail(for: asset)
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.12)
            Image(systemName: asset.kind.iconName)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
        }
    }

    /// Generate a reasonably-sized preview image without blocking the main
    /// thread.
    ///
    /// - Images: `NSImage(contentsOf:)`.
    /// - Videos: try multiple offsets (10% of duration, 5s, 2s, 0.5s) and
    ///   keep the first non-black frame. YouTube music videos and trailers
    ///   commonly open on a pure-black fade-in, so a single 0.5s sample
    ///   produced all-black thumbnails.
    /// - Audio: nil (placeholder icon).
    private static func thumbnail(for asset: AssetCatalog.Asset) async -> NSImage? {
        await Task.detached(priority: .userInitiated) { () -> NSImage? in
            switch asset.kind {
            case .image:
                return NSImage(contentsOf: asset.url)
            case .video:
                let a = AVURLAsset(url: asset.url)
                let gen = AVAssetImageGenerator(asset: a)
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 600, height: 600)
                gen.requestedTimeToleranceBefore = .positiveInfinity
                gen.requestedTimeToleranceAfter = .positiveInfinity

                let durSec = CMTimeGetSeconds(a.duration)
                var candidates: [Double] = [5, 2, 0.5]
                if durSec.isFinite, durSec > 0 {
                    candidates.insert(durSec * 0.1, at: 0)
                }

                for sec in candidates {
                    let time = CMTime(seconds: sec, preferredTimescale: 600)
                    guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else {
                        continue
                    }
                    if !isMostlyBlack(cg) {
                        return NSImage(cgImage: cg, size: .zero)
                    }
                }
                // All sampled frames were black (short clip, fully dark
                // content, etc.) — return the last frame we got anyway so
                // the cell at least shows something.
                let fallback = CMTime(seconds: 1.0, preferredTimescale: 600)
                if let cg = try? gen.copyCGImage(at: fallback, actualTime: nil) {
                    return NSImage(cgImage: cg, size: .zero)
                }
                return nil
            case .audio:
                return nil
            }
        }.value
    }

    /// Quick-and-dirty blackness check: downsample to 16×16 8-bit grayscale
    /// and compute mean luminance. Anything under ~12/255 is treated as
    /// black intro frame. Nonisolated so the detached Task above (which
    /// runs off the main actor) can call it without warnings.
    nonisolated private static func isMostlyBlack(_ image: CGImage) -> Bool {
        let w = 16, h = 16
        var bytes = [UInt8](repeating: 0, count: w * h)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &bytes,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let total = bytes.reduce(0) { $0 + Int($1) }
        let mean = Double(total) / Double(w * h)
        return mean < 12.0
    }
}

// MARK: - Preview Sheet

private struct AssetPreviewSheet: View {
    let asset: AssetCatalog.Asset
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(asset.title).font(.headline).lineLimit(1)
                Spacer()
                Button("Close", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()

            Group {
                switch asset.kind {
                case .image:
                    if let img = NSImage(contentsOf: asset.url) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Text("Could not load image.").foregroundStyle(.secondary)
                    }
                case .video, .audio:
                    MediaPlayerView(
                        url: asset.url,
                        kind: asset.kind == .audio ? .audio : .video
                    )
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
