#if os(macOS)
import SwiftUI
import AppKit

struct AssetPreviewSheet: View {
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
#endif
