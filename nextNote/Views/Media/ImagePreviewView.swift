import SwiftUI

struct ImagePreviewView: View {
    let url: URL

    var body: some View {
        ZStack {
            #if os(macOS)
            Color(NSColor.textBackgroundColor)
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(24)
            } else {
                Text("Could not load image.")
                    .foregroundStyle(.secondary)
            }
            #else
            Color(uiColor: .systemBackground)
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(24)
            } else {
                Text("Could not load image.")
                    .foregroundStyle(.secondary)
            }
            #endif
        }
    }
}
