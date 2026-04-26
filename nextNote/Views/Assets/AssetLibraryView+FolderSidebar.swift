import SwiftUI
#if os(macOS)
import AppKit
#endif

extension AssetLibraryView {
    /// Left pane listing "All", "Loose", then one row per first-level
    /// subfolder under the Assets root. Default category folders
    /// (images / videos / audio / docs / other) always appear even
    /// when empty, so new users see the organization scheme up front.
    var folderSidebar: some View {
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
        #if os(macOS)
        .background(Color(nsColor: .underPageBackgroundColor))
        #endif
    }

    /// Merge default folders with actual disk folders — always show the 5
    /// built-ins, add any user-created extras, alphabetical.
    var sidebarFolderList: [String] {
        var set = Set(LibraryRoots.defaultAssetSubfolders)
        set.formUnion(assetCatalog.folders)
        return set.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func folderIcon(for name: String) -> String {
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
    func folderRow(label: String, icon: String, value: String?) -> some View {
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

    func countForSidebar(folder: String?) -> Int {
        switch folder {
        case .none: return assetCatalog.assets.count
        case .some(let f): return assetCatalog.assets.filter { $0.folder == f }.count
        }
    }
}
