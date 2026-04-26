import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Sidebar shell. Top: Notes tree (flex — dominant). Bottom: three
/// reorderable collapsible trays (Assets, Ebooks, Media) sharing one
/// scroll region. Per-tray bodies and helpers live in `+Assets.swift`,
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

    @State var ebooksExpanded = false
    @State var mediaExpanded = false
    @State var assetsExpanded = false
    @State var expandedFolders: Set<String> = []
    @State var collapsedAssetFolders: Set<String> = []
    @State var showNewAssetFolderAlert = false
    @State var newAssetFolderName = ""
    @State var assetDeleteTarget: AssetCatalog.Asset?
    @State var assetError: String?
    @State var assetsDropTargeted = false
    /// Key of the folder-group row currently being hovered by a drag —
    /// used to tint the header so the user sees the drop target.
    @State var hoveredDropTarget: String? = nil
    @State var bottomTrays: [LibraryTray] = LibrarySidebar.savedBottomTrays()
    @State var draggingTray: LibraryTray?

    enum LibraryTray: String, CaseIterable, Identifiable {
        case assets, ebooks, media
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            NotesSection()
                .frame(maxHeight: .infinity)

            // Trays share one scrollable region so a short window doesn't
            // clip the last tray off-screen.
            Divider()
            ScrollView {
                bottomTrayStack
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

    // MARK: - Reorderable bottom trays
    //
    // User can drag tray headers to reorder Assets / Ebooks / Media. Order
    // persists in UserDefaults so it survives relaunch.

    private static let bottomTrayOrderKey = "nextnote.sidebar.bottomTrayOrder"

    static func savedBottomTrays() -> [LibraryTray] {
        let saved = UserDefaults.standard.string(forKey: bottomTrayOrderKey) ?? ""
        let decoded = saved
            .split(separator: ",")
            .compactMap { LibraryTray(rawValue: String($0)) }
        let missing = LibraryTray.allCases.filter { !decoded.contains($0) }
        let order = decoded + missing
        return order.isEmpty ? LibraryTray.allCases : order
    }

    func saveBottomTrayOrder() {
        let raw = bottomTrays.map(\.rawValue).joined(separator: ",")
        UserDefaults.standard.set(raw, forKey: Self.bottomTrayOrderKey)
    }

    var bottomTrayStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(bottomTrays.enumerated()), id: \.element) { idx, tray in
                if idx > 0 { Divider() }
                bottomTray(tray)
                    .opacity(draggingTray == tray ? 0.55 : 1)
                    .onDrag {
                        draggingTray = tray
                        return NSItemProvider(object: tray.rawValue as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: TrayDropDelegate(
                            target: tray,
                            trays: $bottomTrays,
                            draggingTray: $draggingTray,
                            onReorder: saveBottomTrayOrder
                        )
                    )
            }
        }
    }

    @ViewBuilder
    private func bottomTray(_ tray: LibraryTray) -> some View {
        switch tray {
        case .assets:
            assetsTray
        case .ebooks:
            ebooksTray
        case .media:
            mediaTray
        }
    }

    private struct TrayDropDelegate: DropDelegate {
        let target: LibraryTray
        @Binding var trays: [LibraryTray]
        @Binding var draggingTray: LibraryTray?
        let onReorder: () -> Void

        func dropEntered(info: DropInfo) {
            guard let draggingTray,
                  draggingTray != target,
                  let from = trays.firstIndex(of: draggingTray),
                  let to = trays.firstIndex(of: target)
            else { return }

            withAnimation(.easeInOut(duration: 0.12)) {
                let item = trays.remove(at: from)
                let targetIndex = trays.firstIndex(of: target) ?? to
                trays.insert(item, at: to > from ? min(targetIndex + 1, trays.count) : targetIndex)
            }
            onReorder()
        }

        func performDrop(info: DropInfo) -> Bool {
            draggingTray = nil
            onReorder()
            return true
        }

        func dropExited(info: DropInfo) {
            if draggingTray == target {
                draggingTray = nil
            }
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
