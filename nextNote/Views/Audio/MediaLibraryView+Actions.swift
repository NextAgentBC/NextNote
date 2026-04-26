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
            .help("AI extracts performer + song, renames + moves into Category/Performer folders")

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
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
                useAI: true,
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
