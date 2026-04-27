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
        applyDarkTheme(view)
        view.feed(text: "\u{001B}[38;5;240mnextNote terminal\u{001B}[0m\r\n")
        launch(in: view)
        onMake?(view)
        return view
    }

    private func applyDarkTheme(_ view: LocalProcessTerminalView) {
        // Apple system dark surface (#1C1C1E) — matches macOS dark mode chrome.
        view.nativeBackgroundColor = NSColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1.0)
        view.nativeForegroundColor = NSColor(red: 0.839, green: 0.839, blue: 0.839, alpha: 1.0)
        if let font = NSFont(name: "SF Mono", size: 13) ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) as NSFont? {
            view.font = font
        }
        // ANSI palette — Ghostty-inspired, tuned for #1C1C1E background.
        let palette: [SwiftTerm.Color] = [
            .init(red: 0x3b3b, green: 0x3b3b, blue: 0x3b3b), // black
            .init(red: 0xf1f1, green: 0x4c4c, blue: 0x4c4c), // red
            .init(red: 0x2323, green: 0xd1d1, blue: 0x8b8b), // green
            .init(red: 0xe3e3, green: 0xb3b3, blue: 0x4141), // yellow
            .init(red: 0x3b3b, green: 0x8e8e, blue: 0xeaea), // blue
            .init(red: 0xd6d6, green: 0x7070, blue: 0xd6d6), // magenta
            .init(red: 0x2929, green: 0xb8b8, blue: 0xdbdb), // cyan
            .init(red: 0xe5e5, green: 0xe5e5, blue: 0xe5e5), // white
            .init(red: 0x6666, green: 0x6666, blue: 0x6666), // bright black
            .init(red: 0xf1f1, green: 0x8989, blue: 0x7f7f), // bright red
            .init(red: 0x3f3f, green: 0xb9b9, blue: 0x5050), // bright green
            .init(red: 0xd2d2, green: 0x9999, blue: 0x2222), // bright yellow
            .init(red: 0x7979, green: 0xc0c0, blue: 0xffff), // bright blue
            .init(red: 0xd2d2, green: 0xa8a8, blue: 0xffff), // bright magenta
            .init(red: 0x5656, green: 0xd4d4, blue: 0xdddd), // bright cyan
            .init(red: 0xe6e6, green: 0xeded, blue: 0xf3f3), // bright white
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
