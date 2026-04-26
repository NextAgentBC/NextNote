import Foundation

// Library-wide AI cleanup. For every track, asks the LLM to extract the
// canonical artist + clean song name, renames the file, then moves it into a
// single-level "<Artist>/<Artist> - <Song> [id].ext" layout at `underRoot`.
//
// Single folder level — no category parent. The categorizer uses the set of
// existing folders at `root` as context so "G.E.M." tracks get routed into
// the same "邓紫棋" folder already on disk.
@MainActor
enum LibraryAutoClean {

    struct Outcome: Sendable {
        let scanned: Int
        let renamed: Int
        let skipped: Int
        let failed: Int
    }

    enum Status: Sendable {
        case progress(idx: Int, total: Int, message: String)
        case done(Outcome)
    }

    static func run(
        library: MediaLibrary,
        underRoot root: URL,
        onStatus: @MainActor @escaping (Status) -> Void
    ) async {
        let snapshot = library.tracks
        let total = snapshot.count
        var renamed = 0
        var skipped = 0
        var failed = 0
        // Seed with what's already on disk so the LLM reuses those folder
        // names instead of inventing English aliases for Chinese artists.
        var knownArtists = Set(MediaCategorizer.existingFolders(in: root))

        for (i, track) in snapshot.enumerated() {
            let progressPrefix = "[\(i + 1)/\(total)]"
            onStatus(.progress(idx: i + 1, total: total,
                               message: "\(progressPrefix) Analyzing \(track.title)…"))

            let rawStem = track.url.deletingPathExtension().lastPathComponent
            let videoID = YTDLPMetadataBackfill.extractVideoID(from: track.url)

            do {
                let cleaned = try await MediaCategorizer.cleanAndClassify(
                    title: rawStem,
                    context: nil,
                    existingArtists: knownArtists.sorted()
                )
                guard let rawArtist = cleaned.artist,
                      let rawSong = cleaned.song else {
                    skipped += 1
                    onStatus(.progress(idx: i + 1, total: total,
                                       message: "\(progressPrefix) ⊘ \(track.title) — not enough info"))
                    continue
                }

                // Normalize collabs. When the LLM returned "A, B" we still
                // write it as "A & B" for a per-pairing folder.
                let folderName = artistFolder(from: rawArtist)
                let cleanFolder = MediaCategorizer.sanitize(folderName).nonEmpty
                    ?? MediaCategorizer.sanitize(rawArtist).nonEmpty
                    ?? "Unknown"
                let cleanArtist = MediaCategorizer.sanitize(rawArtist)
                let cleanSong = MediaCategorizer.sanitize(rawSong)

                var newBase = "\(cleanArtist) - \(cleanSong)"
                if let vid = videoID { newBase += " [\(vid)]" }

                let ext = track.url.pathExtension
                let newFilename = ext.isEmpty ? newBase : "\(newBase).\(ext)"

                let destDir = root.appendingPathComponent(cleanFolder, isDirectory: true)
                try FileManager.default.createDirectory(
                    at: destDir, withIntermediateDirectories: true
                )

                var destURL = destDir.appendingPathComponent(newFilename)
                if destURL.path == track.url.path {
                    let newDisplay = "\(cleanArtist) — \(cleanSong)"
                    library.renameTrack(id: track.id, to: newDisplay)
                    knownArtists.insert(cleanFolder)
                    skipped += 1
                    onStatus(.progress(idx: i + 1, total: total,
                                       message: "\(progressPrefix) = \(newDisplay) (already aligned)"))
                    continue
                }
                if FileManager.default.fileExists(atPath: destURL.path) {
                    destURL = FileDestinations.unique(base: newBase, ext: ext, in: destDir)
                }

                try FileManager.default.moveItem(at: track.url, to: destURL)
                let newDisplay = "\(cleanArtist) — \(cleanSong)"
                library.updateTrackURL(id: track.id, newURL: destURL, newTitle: newDisplay)
                knownArtists.insert(cleanFolder)
                renamed += 1
                onStatus(.progress(idx: i + 1, total: total,
                                   message: "\(progressPrefix) ✓ \(newDisplay) → \(cleanFolder)"))
            } catch {
                failed += 1
                onStatus(.progress(idx: i + 1, total: total,
                                   message: "\(progressPrefix) ✗ \(track.title): \(error.localizedDescription)"))
            }
        }

        onStatus(.done(Outcome(
            scanned: total, renamed: renamed, skipped: skipped, failed: failed
        )))
    }

    // MARK: - Helpers

    /// Normalize "A, B, C" collabs to "A & B & C" so each unique pairing
    /// gets its own folder instead of a separate folder per comma order.
    private static func artistFolder(from raw: String) -> String {
        let parts = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if parts.isEmpty { return raw.trimmingCharacters(in: .whitespaces) }
        if parts.count == 1 { return parts[0] }
        return parts.joined(separator: " & ")
    }

}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
