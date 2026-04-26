#if os(macOS)
import SwiftUI
import SwiftTerm
import AppKit

// Embedded terminal hosted in the main window. Phase B of AI_PLAN.md —
// the CLI is a first-class pane so Claude Code / Gemini CLI workflows stay
// in-app. Process cwd is pinned to the vault root, so slash-skills resolve
// relative paths correctly.
struct TerminalPane: NSViewRepresentable {
    let workingDirectory: URL?

    /// One-shot command injected by the command palette. Setter is on the
    /// binding owner (AppState). Pane consumes the value and clears it.
    @Binding var pendingCommand: String?

    /// Optional ref-out so chrome (close / clear buttons, header) can reach
    /// back into the pane for actions like ANSI clear.
    var onMake: ((LocalProcessTerminalView) -> Void)? = nil

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        applyLightTheme(view)
        view.feed(text: "\u{001B}[90mnextNote terminal — cwd is your vault root\u{001B}[0m\r\n")
        launch(in: view)
        onMake?(view)
        return view
    }

    /// Match the rest of the app (light chrome). SwiftTerm defaults to a
    /// dark terminal; force a near-white background + near-black foreground
    /// plus a muted ANSI palette so colorized CLI output stays legible
    /// against a bright surface.
    private func applyLightTheme(_ view: LocalProcessTerminalView) {
        view.nativeBackgroundColor = NSColor(white: 0.98, alpha: 1.0)
        view.nativeForegroundColor = NSColor(white: 0.12, alpha: 1.0)
        // 16-color ANSI palette tuned for light backgrounds (Solarized-light-ish).
        let palette: [SwiftTerm.Color] = [
            .init(red: 0x0000, green: 0x0000, blue: 0x0000), // black
            .init(red: 0xc0c0, green: 0x1717, blue: 0x1717), // red
            .init(red: 0x1e1e, green: 0x8080, blue: 0x2020), // green
            .init(red: 0xa0a0, green: 0x5d5d, blue: 0x0a0a), // yellow
            .init(red: 0x1d1d, green: 0x4e4e, blue: 0xd8d8), // blue
            .init(red: 0x8c8c, green: 0x1c1c, blue: 0x9e9e), // magenta
            .init(red: 0x0808, green: 0x7878, blue: 0x8c8c), // cyan
            .init(red: 0xbdbd, green: 0xbdbd, blue: 0xbdbd), // white (light grey)
            .init(red: 0x5a5a, green: 0x5a5a, blue: 0x5a5a), // bright black
            .init(red: 0xe0e0, green: 0x2b2b, blue: 0x2b2b), // bright red
            .init(red: 0x2828, green: 0xa0a0, blue: 0x3030), // bright green
            .init(red: 0xb9b9, green: 0x7070, blue: 0x1c1c), // bright yellow
            .init(red: 0x3e3e, green: 0x6e6e, blue: 0xe9e9), // bright blue
            .init(red: 0xb2b2, green: 0x2929, blue: 0xc3c3), // bright magenta
            .init(red: 0x1111, green: 0x9494, blue: 0xa8a8), // bright cyan
            .init(red: 0x3434, green: 0x3434, blue: 0x3434)  // bright white (dark text)
        ]
        view.installColors(palette)
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        if let cmd = pendingCommand, !cmd.isEmpty {
            nsView.send(txt: cmd + "\n")
            DispatchQueue.main.async { self.pendingCommand = nil }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }

    // MARK: - Launch

    private func launch(in view: LocalProcessTerminalView) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        // Ensure login shell picks up Homebrew paths (yt-dlp, ffmpeg, claude,
        // gemini installed via brew live under /opt/homebrew/bin on Apple
        // silicon, /usr/local/bin on Intel). Login shell + path prefix covers
        // both without assuming the user's profile sets it.
        env.append("HOMEBREW_PREFIX=/opt/homebrew")

        let cwd = workingDirectory?.path ?? NSHomeDirectory()
        // sh -c wrapper gives us a reliable chdir without SwiftTerm-specific
        // cwd plumbing — same trick `make`, tmux, and IDE terminals use.
        let quotedCwd = shellQuote(cwd)
        let quotedShell = shellQuote(shell)
        let script = "cd \(quotedCwd) && exec \(quotedShell) -l"

        view.startProcess(
            executable: "/bin/sh",
            args: ["-c", script],
            environment: env,
            execName: "sh"
        )
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let owner: TerminalPane
        init(owner: TerminalPane) { self.owner = owner }

        // MARK: LocalProcessTerminalViewDelegate
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            if let code = exitCode, code != 0 {
                source.feed(text: "\r\n\u{001B}[91m[shell exited with code \(code)]\u{001B}[0m\r\n")
            } else {
                source.feed(text: "\r\n\u{001B}[90m[shell exited]\u{001B}[0m\r\n")
            }
        }
    }
}
#endif
