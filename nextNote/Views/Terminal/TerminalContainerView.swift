#if os(macOS)
import SwiftUI
import AppKit
import SwiftTerm

// Wraps TerminalPane in a light chrome: title strip with cwd, clear, and
// close controls. Without this the raw SwiftTerm surface has no way to
// dismiss itself from inside the pane — users had to go back to ⌘⇧T or
// the menubar. One-strip, minimal controls, stays out of the way.
struct TerminalContainerView: View {
    @EnvironmentObject private var appState: AppState
    let workingDirectory: URL?

    @State private var terminalRef: LocalProcessTerminalView?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TerminalPane(
                workingDirectory: workingDirectory,
                pendingCommand: $appState.pendingTerminalCommand,
                onMake: { terminalRef = $0 }
            )
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(displayPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                clearTerminal()
            } label: {
                Image(systemName: "eraser")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Clear terminal")

            Button {
                appState.showTerminal = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Close terminal (⌘⇧T)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var displayPath: String {
        guard let url = workingDirectory else { return "~" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = url.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    private func clearTerminal() {
        // ANSI: CSI 2 J erases screen, CSI H moves cursor home. Shell history
        // stays; only the rendered buffer clears — same as `clear` / ⌘K in
        // Terminal.app.
        terminalRef?.feed(text: "\u{001B}[2J\u{001B}[H")
    }
}
#endif
