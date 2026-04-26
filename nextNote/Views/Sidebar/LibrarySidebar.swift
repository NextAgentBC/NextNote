import SwiftUI
import SwiftData

/// Sidebar shell. Top: Notes tree (flex — dominant). Bottom: three
/// collapsible trays (Assets, Ebooks, Media) sharing one scroll region.
/// Per-tray bodies and helpers live in `LibrarySidebar+Assets.swift`,
/// `+Media.swift`, `+Ebooks.swift`. Shared row chrome (header, subheader,
/// empty hint, friendly path) is in `+Shared.swift`.
struct LibrarySidebar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var vault: VaultStore
    @EnvironmentObject var libraryRoots: LibraryRoots
    @EnvironmentObject var assetCatalog: AssetCatalog
    @StateObject var mediaLibrary = MediaLibrary.shared
    @Environment(\.modelContext) var modelContext

    @Query(sort: \Book.title) var books: [Book]

    @State var ebooksExpanded = true
    @State var mediaExpanded = true
    @State var assetsExpanded = true
    @State var expandedFolders: Set<String> = []
    @State var collapsedAssetFolders: Set<String> = []
    @State var showNewAssetFolderAlert = false
    @State var newAssetFolderName = ""
    @State var assetDeleteTarget: AssetCatalog.Asset?
    @State var assetError: String?
    @State var assetsDropTargeted = false
    /// Key of the folder-group row currently being hovered by a drag — used
    /// to tint the header so the user sees the drop target.
    @State var hoveredDropTarget: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            NotesSection()
                .frame(maxHeight: .infinity)

            // Trays share one scrollable region so a short window doesn't
            // clip the last tray off-screen.
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    assetsTray
                    Divider()
                    ebooksTray
                    Divider()
                    mediaTray
                }
            }
            .frame(maxHeight: 420)
        }
        .onChange(of: appState.triggerRescanLibrary) { _, v in
            if v { appState.triggerRescanLibrary = false }
        }
        .alert("New Asset Folder", isPresented: $showNewAssetFolderAlert) {
            TextField("Name", text: $newAssetFolderName)
            Button("Cancel", role: .cancel) { newAssetFolderName = "" }
            Button("Create") { createAssetFolder() }
        }
        .alert("Move Asset to Trash?", isPresented: .init(
            get: { assetDeleteTarget != nil },
            set: { if !$0 { assetDeleteTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                if let asset = assetDeleteTarget {
                    trashAsset(asset)
                }
                assetDeleteTarget = nil
            }
        } message: {
            Text(assetDeleteTarget?.title ?? "")
        }
        .alert("Asset Error", isPresented: .init(
            get: { assetError != nil },
            set: { if !$0 { assetError = nil } }
        )) {
            Button("OK") { assetError = nil }
        } message: {
            Text(assetError ?? "")
        }
    }
}

/// Asset folder group used by the Assets tray. Top-level so extensions
/// across files can refer to it.
struct AssetFolderGroup: Identifiable {
    let id: String
    let folder: String
    let title: String
    let assets: [AssetCatalog.Asset]
}
