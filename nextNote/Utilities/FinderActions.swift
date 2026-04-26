import Foundation
#if os(macOS)
import AppKit
#endif

enum FinderActions {
    /// Reveal a single file or folder in Finder. No-op on non-mac or when nil.
    static func reveal(_ url: URL?) {
        #if os(macOS)
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    static func reveal(_ urls: [URL]) {
        #if os(macOS)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        #endif
    }
}
