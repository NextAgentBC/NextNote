import Foundation
#if os(macOS)
import AppKit
#endif

enum PasteboardActions {
    /// Replace the system pasteboard contents with `text`. No-op on non-mac.
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// Convenience: copy a markdown image embed `![title](path)` to the
    /// pasteboard. Used by Asset and Vault embed actions.
    static func copyMarkdownEmbed(title: String, path: String) {
        copy("![\(title)](\(path))")
    }
}
