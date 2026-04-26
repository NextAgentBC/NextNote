#if os(macOS)
import SwiftUI
import AppKit

struct AssetCell: View {
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
#endif
