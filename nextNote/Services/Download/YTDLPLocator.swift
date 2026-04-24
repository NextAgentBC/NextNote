import Foundation
import AppKit

// Resolves the user's yt-dlp binary location. The sandbox blocks us from
// scanning /opt/homebrew/bin etc. directly — the user picks the binary once
// via NSOpenPanel, and we keep a security-scoped bookmark so subsequent
// launches can re-grant access. The "choose a folder" companion handles the
// download destination the same way.
@MainActor
final class YTDLPLocator: ObservableObject {
    static let shared = YTDLPLocator()

    @Published private(set) var binaryURL: URL?
    @Published private(set) var ffmpegURL: URL?
    @Published private(set) var downloadFolderURL: URL?

    private var binaryScope: URL?
    private var ffmpegScope: URL?
    private var folderScope: URL?

    private static let binaryKey = "ytdlp.binary.bookmark"
    private static let ffmpegKey = "ytdlp.ffmpeg.bookmark"
    private static let folderKey = "ytdlp.downloadFolder.bookmark"

    private init() {
        restoreBinary()
        restoreFFmpeg()
        restoreFolder()

        // Sandbox is off (see nextNote.entitlements) — we can spawn any
        // binary on disk without a security-scoped bookmark. Auto-adopt
        // detected Homebrew paths so the user doesn't have to click
        // Choose… every fresh install. Manual override still works.
        autoAdoptDetectedBinariesIfNeeded()
    }

    private func autoAdoptDetectedBinariesIfNeeded() {
        let fm = FileManager.default
        if binaryURL == nil,
           let detected = Self.detectedBinaryPath,
           fm.isExecutableFile(atPath: detected) {
            adoptBinary(URL(fileURLWithPath: detected))
        }
        if ffmpegURL == nil,
           let detected = Self.detectedFFmpegPath,
           fm.isExecutableFile(atPath: detected) {
            adoptFFmpeg(URL(fileURLWithPath: detected))
        }
    }

    deinit {
        binaryScope?.stopAccessingSecurityScopedResource()
        ffmpegScope?.stopAccessingSecurityScopedResource()
        folderScope?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Binary

    /// Common Homebrew install paths for yt-dlp. Sandbox still requires the
    /// user to pick via NSOpenPanel to get a bookmark, but we open the panel
    /// pointed at whichever exists so they can confirm in one click.
    static let candidateBinaryPaths: [String] = [
        "/opt/homebrew/bin/yt-dlp",   // Apple Silicon
        "/usr/local/bin/yt-dlp",      // Intel / MacPorts
    ]

    /// First candidate path that actually exists on disk, or nil.
    static var detectedBinaryPath: String? {
        candidateBinaryPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    enum PickError: LocalizedError {
        case notExecutable(URL)

        var errorDescription: String? {
            switch self {
            case .notExecutable(let url):
                return "\"\(url.lastPathComponent)\" isn't an executable. Pick the yt-dlp binary itself (not a video or script)."
            }
        }
    }

    @Published var lastPickError: String?

    func pickBinary() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Pick the yt-dlp binary (typically /opt/homebrew/bin/yt-dlp)."
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true

        // Land on whichever candidate exists. Falling back to /opt/homebrew/bin
        // even if yt-dlp isn't there yet keeps the user one `brew install`
        // away from being done.
        if let p = Self.detectedBinaryPath {
            panel.directoryURL = URL(fileURLWithPath: (p as NSString).deletingLastPathComponent)
            panel.nameFieldStringValue = (p as NSString).lastPathComponent
        } else {
            panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        }

        let resp = await withCheckedContinuation { (cont: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { cont.resume(returning: $0) }
            } else {
                cont.resume(returning: panel.runModal())
            }
        }
        guard resp == .OK, let url = panel.url else { return }

        // Guard against re-picking an mp4 or script by accident — we only
        // want an executable file. NSOpenPanel can't filter on exec bit.
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            lastPickError = PickError.notExecutable(url).errorDescription
            return
        }
        lastPickError = nil
        adoptBinary(url)
    }

    private func adoptBinary(_ url: URL) {
        binaryScope?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else { return }
        binaryScope = url
        binaryURL = url
        let bm = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bm, forKey: Self.binaryKey)
    }

    private func restoreBinary() {
        guard let data = UserDefaults.standard.data(forKey: Self.binaryKey) else { return }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return }
        if url.startAccessingSecurityScopedResource() {
            binaryScope = url
        }
        binaryURL = url
    }

    // MARK: - ffmpeg (optional but unlocks max-quality merged downloads)

    static let candidateFFmpegPaths: [String] = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
    ]

    static var detectedFFmpegPath: String? {
        candidateFFmpegPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    func pickFFmpeg() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Pick the ffmpeg binary (enables 4K/max-quality merged downloads)."
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true

        if let p = Self.detectedFFmpegPath {
            panel.directoryURL = URL(fileURLWithPath: (p as NSString).deletingLastPathComponent)
            panel.nameFieldStringValue = (p as NSString).lastPathComponent
        } else {
            panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        }

        let resp = await withCheckedContinuation { (cont: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { cont.resume(returning: $0) }
            } else {
                cont.resume(returning: panel.runModal())
            }
        }
        guard resp == .OK, let url = panel.url else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            lastPickError = PickError.notExecutable(url).errorDescription
            return
        }
        lastPickError = nil
        adoptFFmpeg(url)
    }

    private func adoptFFmpeg(_ url: URL) {
        ffmpegScope?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else { return }
        ffmpegScope = url
        ffmpegURL = url
        let bm = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bm, forKey: Self.ffmpegKey)
    }

    private func restoreFFmpeg() {
        guard let data = UserDefaults.standard.data(forKey: Self.ffmpegKey) else { return }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return }
        if url.startAccessingSecurityScopedResource() {
            ffmpegScope = url
        }
        ffmpegURL = url
    }

    // MARK: - Download folder

    func pickDownloadFolder() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Pick a folder for YouTube downloads."

        let resp = await withCheckedContinuation { (cont: CheckedContinuation<NSApplication.ModalResponse, Never>) in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { cont.resume(returning: $0) }
            } else {
                cont.resume(returning: panel.runModal())
            }
        }
        guard resp == .OK, let url = panel.url else { return }
        adoptFolder(url)
    }

    private func adoptFolder(_ url: URL) {
        folderScope?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else { return }
        folderScope = url
        downloadFolderURL = url
        let bm = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(bm, forKey: Self.folderKey)
    }

    private func restoreFolder() {
        guard let data = UserDefaults.standard.data(forKey: Self.folderKey) else { return }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return }
        if url.startAccessingSecurityScopedResource() {
            folderScope = url
        }
        downloadFolderURL = url
    }
}
