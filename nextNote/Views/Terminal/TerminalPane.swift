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

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.feed(text: "\u{001B}[90mnextNote terminal — cwd is your vault root\u{001B}[0m\r\n")
        launch(in: view)
        return view
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
