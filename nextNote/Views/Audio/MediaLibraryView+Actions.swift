import SwiftUI

extension MediaLibraryView {
    /// Inline action strip at the top of the sidebar — sheet-presented
    /// NavigationSplitView doesn't reliably surface .toolbar items on
    /// macOS, so these live in view space instead.
    var libraryActionsBar: some View {
        HStack(spacing: 6) {
            Button {
                runBackfill()
            } label: {
                HStack(spacing: 4) {
                    if isBackfilling {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "character.bubble")
                    }
                    Text("Restore Titles")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isBackfilling || YTDLPLocator.shared.binaryURL == nil)
            .help("Re-fetch Chinese/real titles via yt-dlp")

            Button {
                runAutoClean()
            } label: {
                HStack(spacing: 4) {
                    if isAutoCleaning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "wand.and.sparkles")
                    }
                    Text("Auto-Clean")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isAutoCleaning || locator.downloadFolderURL == nil)
            .help("Local string parser — extracts artist + song, renames + moves into <Artist>/ folders")

            Button {
                tidyWithClaude()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles.tv")
                    Text("Tidy with Claude")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(tidyTargetRoot() == nil)
            .help("Open the embedded terminal and ask Claude to organize the library — handles edge cases the local parser misses")

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// Pick the directory Claude should organize. Prefers the configured
    /// Media root (where Auto-Clean already lands files); falls back to
    /// the yt-dlp download folder if Media isn't set up yet.
    func tidyTargetRoot() -> URL? {
        libraryRoots.mediaRoot ?? library.ambientFolderURL ?? locator.downloadFolderURL
    }

    /// Drop a pre-baked prompt into the embedded terminal so Claude CLI
    /// can crawl the media library, propose a rename plan, and apply it
    /// after user confirmation. Closes the sheet so the terminal pane is
    /// visible.
    func tidyWithClaude() {
        guard let root = tidyTargetRoot() else { return }
        let prompt = TidyMediaPrompt.build(rootPath: root.path)
        appState.showTerminal = true
        appState.pendingTerminalCommand = "claude " + shellEscape(prompt)
        dismiss()
    }

    /// Single-quote escape for shell — fine for the prompt text since we
    /// only need to neutralize embedded single quotes.
    private func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func runAutoClean() {
        guard let root = locator.downloadFolderURL else { return }
        isAutoCleaning = true
        autoCleanStatus = "Starting…"
        Task {
            await LibraryAutoClean.run(library: library, underRoot: root) { status in
                switch status {
                case .progress(_, _, let msg):
                    autoCleanStatus = msg
                case .done(let outcome):
                    isAutoCleaning = false
                    autoCleanStatus = "Done — \(outcome.renamed) renamed, \(outcome.skipped) skipped, \(outcome.failed) failed (of \(outcome.scanned))."
                }
            }
        }
    }

    func runBackfill() {
        guard let binary = YTDLPLocator.shared.binaryURL else { return }
        isBackfilling = true
        backfillStatus = "Starting…"
        Task {
            await YTDLPMetadataBackfill.run(library: library, binary: binary) { status in
                switch status {
                case .progress(let idx, let total, let message):
                    backfillStatus = "[\(idx)/\(total)] \(message)"
                case .done(let outcome):
                    isBackfilling = false
                    backfillStatus = "Done — \(outcome.updated) updated, \(outcome.skipped) skipped, \(outcome.failed) failed (of \(outcome.scanned) candidates)."
                }
            }
        }
    }

    func generatePlaylistsFromFolders() {
        guard let root = library.ambientFolderURL else { return }
        isGeneratingPlaylists = true
        playlistGenStatus = "Starting…"
        Task {
            let result = await library.generatePlaylistsFromFolders(
                root: root,
                onStatus: { status in
                    playlistGenStatus = status
                }
            )
            isGeneratingPlaylists = false
            playlistGenStatus = "Created \(result.created), updated \(result.updated)."
        }
    }

    func autoOrganize(_ tracks: [Track]) {
        guard let root = locator.downloadFolderURL else { return }
        isOrganizing = true
        organizeStatus = "Starting…"
        Task {
            var moved = 0
            var failed = 0
            for t in tracks {
                await MainActor.run {
                    organizeStatus = "Classifying \(t.title)…"
                }
                do {
                    let newURL = try await MediaCategorizer.organize(url: t.url, underRoot: root)
                    await MainActor.run {
                        library.updateTrackURL(id: t.id, newURL: newURL)
                        moved += 1
                    }
                } catch {
                    await MainActor.run {
                        failed += 1
                        organizeStatus = "\(t.title): \(error.localizedDescription)"
                    }
                }
            }
            await MainActor.run {
                isOrganizing = false
                organizeStatus = "Organized \(moved), failed \(failed)."
            }
        }
    }
}
