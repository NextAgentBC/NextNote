import SwiftUI

#if os(macOS)
import AppKit

/// Hosts the AI chat terminal in a standalone NSWindow. Mirrors the pattern
/// used by `DrawingWindowController` and `PreviewWindowController` —
/// singleton, freely resizable, can be screen-shared independently of the
/// main editor window.
@MainActor
final class ChatTerminalWindowController {
    static let shared = ChatTerminalWindowController()
    private var controller: NSWindowController?

    func show(appState: AppState) {
        if let c = controller, let w = c.window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = ChatTerminalView()
            .environmentObject(appState)

        let host = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AI Terminal"
        window.titlebarAppearsTransparent = true
        window.contentViewController = host
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("nextnote.aiterminal.window")
        // Match the inner terminal background so the title bar blends in
        // instead of giving us a chrome stripe.
        window.backgroundColor = NSColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1.0)

        let c = NSWindowController(window: window)
        controller = c
        c.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        controller?.close()
        controller = nil
    }

    var isOpen: Bool { controller?.window?.isVisible == true }
}

#endif
