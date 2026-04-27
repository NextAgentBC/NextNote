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
            TerminalPane(
                workingDirectory: workingDirectory,
                pendingCommand: $appState.pendingTerminalCommand,
                onMake: { terminalRef = $0 }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(spacing: 6) {
            // Status dot
            Circle()
                .fill(Color(red: 0.22, green: 0.82, blue: 0.42))
                .frame(width: 7, height: 7)

            Image(systemName: "terminal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            Text(displayPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                clearTerminal()
            } label: {
                Image(systemName: "eraser.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Clear terminal")

            Button {
                appState.showTerminal = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close terminal (⌘⇧T)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            // Glass header blending into dark terminal below
            ZStack {
                Color(red: 0.145, green: 0.145, blue: 0.153)
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.3)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
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
