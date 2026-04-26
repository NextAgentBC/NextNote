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
/// Header / folder sidebar / grid / actions live in adjacent extension
/// files (+Header, +FolderSidebar, +Grid, +Actions).
struct AssetLibraryView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var libraryRoots: LibraryRoots
    @EnvironmentObject var assetCatalog: AssetCatalog

    @State var kindFilter: KindFilter = .all
    @State var searchText: String = ""
    @State var isDropTargeting: Bool = false
    @State var importError: String?
    @State var previewAsset: AssetCatalog.Asset?
    @State var deleteTarget: AssetCatalog.Asset?
    /// nil → All folders. Empty string → loose files at the root (shown
    /// under "Loose"). Non-empty → that specific first-level subfolder.
    @State var folderFilter: String? = nil
    @State var showNewFolderAlert: Bool = false
    @State var newFolderName: String = ""

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

    let columns = [
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
}
