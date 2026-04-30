import SwiftUI

#if os(macOS)
import AppKit

/// Standalone NSWindow that mirrors the active note's markdown preview.
/// Borrows the same `MarkdownPreviewView` + 350 ms debounce coordinator that
/// the in-editor split mode uses, so live edits stream to the floating
/// window without a per-keystroke reload thrash.
///
/// Use case: video-call screen-share. The user shares only this window so
/// the audience sees the rendered preview while typing happens in the main
/// window. Toggle "Stay on top" to keep it visible over Zoom / Meet.
@MainActor
final class PreviewWindowController {
    static let shared = PreviewWindowController()

    private var controller: NSWindowController?
    private var alwaysOnTopKey = "nextnote.preview.alwaysOnTop"

    /// Open or focus the floating preview. Re-opening an existing window
    /// just brings it forward.
    func show(
        appState: AppState,
        vault: VaultStore,
        libraryRoots: LibraryRoots,
        preferences: UserPreferences
    ) {
        NSLog("[PreviewWindowController] show() called")
        if let c = controller, let w = c.window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = FloatingPreviewHost()
            .environmentObject(appState)
            .environmentObject(vault)
            .environmentObject(libraryRoots)
            .environmentObject(preferences)

        let hosting = NSHostingController(rootView: host)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Floating Preview"
        window.contentViewController = hosting
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        // Persist size + position across launches so the user's resize sticks.
        window.setFrameAutosaveName("nextnote.preview.window")

        if UserDefaults.standard.bool(forKey: alwaysOnTopKey) {
            window.level = .floating
        }

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

    /// Flip between `.normal` and `.floating` window levels. Persists.
    func toggleAlwaysOnTop() {
        guard let w = controller?.window else { return }
        let next = w.level != .floating
        w.level = next ? .floating : .normal
        UserDefaults.standard.set(next, forKey: alwaysOnTopKey)
    }

    var isAlwaysOnTop: Bool {
        controller?.window?.level == .floating
    }

    var isOpen: Bool { controller?.window?.isVisible == true }
}

/// SwiftUI host hosted inside `PreviewWindowController`. Reads the active
/// tab from `AppState` and rebinds the preview every time the user types
/// or switches tabs in the main window.
struct FloatingPreviewHost: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var preferences: UserPreferences

    @State private var pinned: Bool = UserDefaults.standard.bool(forKey: "nextnote.preview.alwaysOnTop")

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.richtext")
                .foregroundStyle(.secondary)
            Text(currentTitle)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                pinned.toggle()
                PreviewWindowController.shared.toggleAlwaysOnTop()
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .foregroundStyle(pinned ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help(pinned ? "Window stays above other apps — click to unpin" : "Pin window above other apps")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let tab = appState.activeTab,
           tab.bookID == nil,
           tab.document.fileType == .md {
            MarkdownPreviewView(
                content: tab.document.content,
                baseURL: noteBaseURL(for: tab)
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Open a markdown note in the main window to preview it here.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var currentTitle: String {
        if let tab = appState.activeTab {
            let t = tab.document.title
            if !t.isEmpty { return t }
        }
        return "Preview"
    }

    /// Same logic as `EditorContentRouter.noteBaseURL(for:)`. Duplicated
    /// here because the floating window doesn't inherit ContentView's
    /// extension scope and we don't want to pull `MarkdownPreviewView`'s
    /// resolver into a shared helper just yet.
    private func noteBaseURL(for tab: TabItem) -> URL? {
        guard preferences.vaultMode,
              let relPath = appState.vaultPath(forTabId: tab.id),
              let fileURL = vault.url(for: relPath)
        else { return nil }
        return fileURL.deletingLastPathComponent()
    }
}

#endif
