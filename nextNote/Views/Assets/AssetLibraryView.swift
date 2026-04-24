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
            content
        }
        .frame(minWidth: 760, minHeight: 520)
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

    private var header: some View {
        HStack(spacing: 10) {
            Text("Asset Library")
                .font(.title2.bold())

            Text("\(filteredAssets.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Picker("", selection: $kindFilter) {
                ForEach(KindFilter.allCases) { k in
                    Text(k.rawValue).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            Button {
                openImportPanel()
            } label: {
                Label("Import…", systemImage: "square.and.arrow.down")
            }

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
        .padding(12)
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
                        .onTapGesture(count: 2) { previewAsset = asset }
                        .contextMenu {
                            Button("Preview") { previewAsset = asset }
                            Button("Reveal in Finder") { revealInFinder(asset) }
                            Divider()
                            Button("Copy Markdown Embed") {
                                copyEmbedMarkdown(asset)
                            }
                            Divider()
                            Button("Move to Trash", role: .destructive) {
                                deleteTarget = asset
                            }
                        }
                        // URL is the simplest Transferable form. When the
                        // drop lands on our editor's NSTextView (registered
                        // for .fileURL), the Coordinator reads the file
                        // URL and inserts the Markdown embed syntax.
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
        let byKind = assetCatalog.filtered(kind: kindFilter.mediaKind)
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return byKind }
        return byKind.filter { $0.title.lowercased().contains(q) }
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
            guard MediaKind.from(url: src) != nil else {
                skipped.append(src.lastPathComponent)
                continue
            }
            let dest = uniqueDestination(for: src.lastPathComponent, in: root)
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
            // Flag wake-up also refreshes the main sidebar, so Assets
            // tray (if the user chooses to expose it later) stays in sync.
            await MainActor.run { appState.triggerRescanLibrary = true }
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
        let dest = uniqueDestination(for: "pasted-\(stamp).png", in: root)
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
    /// thread. Images load via NSImage directly; videos grab a frame around
    /// 0.5s in (skips black intro frames common in rendered exports);
    /// audio falls back to the SF Symbol placeholder.
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
                let time = CMTime(seconds: 0.5, preferredTimescale: 600)
                guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else {
                    return nil
                }
                return NSImage(cgImage: cg, size: .zero)
            case .audio:
                return nil
            }
        }.value
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
