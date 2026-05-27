import Foundation

// Apply a `Plan` to the on-disk library — library record removal,
// empty-folder cleanup, artist-folder merges (move + filename rewrite),
// and cross-folder duplicate trim. Returns an `Outcome` tally.
extension LibraryReconciler {

    struct Outcome {
        var deadPruned: Int = 0
        var libDupsPruned: Int = 0
        var emptyFoldersRemoved: Int = 0
        var foldersMerged: Int = 0
        var foldersRenamed: Int = 0
        var filesMoved: Int = 0
        var filesRenamed: Int = 0
        var filesTrashed: Int = 0
        var failed: [String] = []
    }

    static func apply(
        _ plan: Plan,
        underRoot root: URL,
        library: MediaLibrary,
        progress: ((String) -> Void)? = nil
    ) async -> Outcome {
        var out = Outcome()

        // Phase 1 — library hygiene (no disk effect).
        for d in plan.deadTracks where d.apply {
            progress?("Removing dead track: \(d.title)")
            library.removeTrack(id: d.id)
            out.deadPruned += 1
        }
        for libDup in plan.duplicateLibraryRecords where libDup.apply {
            for (i, id) in libDup.trackIDs.enumerated() where i != libDup.keepIndex {
                library.removeTrack(id: id)
                out.libDupsPruned += 1
            }
        }

        // Phase 2a — empty / orphan folder cleanup.
        for ef in plan.emptyFolders where ef.apply {
            let dir = root.appendingPathComponent(ef.name, isDirectory: true)
            do {
                try FileManager.default.removeItem(at: dir)
                out.emptyFoldersRemoved += 1
            } catch {
                out.failed.append("\(ef.name)/: \(error.localizedDescription)")
            }
        }

        // Phase 2b — folder merges + renames. Move every file into the
        // canonical folder, rewriting the `<old> - song.ext` prefix to
        // `<new> - song.ext` so filenames stay consistent. When canonical
        // folder is the same as the alias (i.e. a single-folder rename
        // proposal), still go through the move loop so the files get
        // renamed.
        for merge in plan.merges where merge.apply {
            progress?("Reconciling \(merge.canonical)…")
            let canonicalDir = root.appendingPathComponent(merge.canonical, isDirectory: true)
            try? FileManager.default.createDirectory(at: canonicalDir, withIntermediateDirectories: true)

            // Aliases includes the canonical itself only when AI mistakenly
            // listed it (we strip that earlier). For a "rename only" plan,
            // the original folder name shows up as an alias and gets handled
            // here.
            let sourcesToProcess = merge.aliases
            var didChange = false
            for alias in sourcesToProcess {
                let aliasDir = root.appendingPathComponent(alias, isDirectory: true)
                guard FileManager.default.fileExists(atPath: aliasDir.path) else { continue }
                let files = (try? FileManager.default.contentsOfDirectory(atPath: aliasDir.path)) ?? []
                for f in files where !f.hasPrefix(".") {
                    let src = aliasDir.appendingPathComponent(f)
                    let renamed = rewriteFilenamePrefix(f, oldArtist: alias, newArtist: merge.canonical)
                    let dst = FileDestinations.unique(for: renamed, in: canonicalDir)
                    if dst.standardizedFileURL.path == src.standardizedFileURL.path { continue }
                    do {
                        try FileManager.default.moveItem(at: src, to: dst)
                        if renamed != f { out.filesRenamed += 1 } else { out.filesMoved += 1 }
                        if let track = library.tracks.first(where: { $0.url.path == src.path }) {
                            library.updateTrackURL(id: track.id, newURL: dst)
                        }
                        didChange = true
                    } catch {
                        out.failed.append("\(src.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                let remaining = (try? FileManager.default.contentsOfDirectory(atPath: aliasDir.path)) ?? []
                if remaining.filter({ !$0.hasPrefix(".") }).isEmpty {
                    try? FileManager.default.removeItem(at: aliasDir)
                }
            }
            if didChange {
                if sourcesToProcess.count == 1 && sourcesToProcess.first != merge.canonical {
                    out.foldersRenamed += 1
                } else {
                    out.foldersMerged += 1
                }
            }
        }

        // Phase 3 — duplicate trim. Keep the chosen file, trash the rest.
        for dup in plan.duplicates where dup.apply {
            guard dup.relativePaths.indices.contains(dup.keepIndex) else { continue }
            for (i, rel) in dup.relativePaths.enumerated() where i != dup.keepIndex {
                progress?("Trashing duplicate: \(rel)")
                let url = resolvePath(rel, postMergeRoot: root, plan: plan)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                if let track = library.tracks.first(where: { $0.url.path == url.path }) {
                    _ = library.trashTrack(id: track.id)
                    out.filesTrashed += 1
                } else {
                    do {
                        var trashed: NSURL?
                        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
                        out.filesTrashed += 1
                    } catch {
                        out.failed.append("\(rel): \(error.localizedDescription)")
                    }
                }
            }
        }

        return out
    }

    /// Resolve a relative path that might have been moved by a folder merge.
    private static func resolvePath(_ rel: String, postMergeRoot root: URL, plan: Plan) -> URL {
        let original = root.appendingPathComponent(rel)
        if FileManager.default.fileExists(atPath: original.path) { return original }
        let comps = rel.split(separator: "/", maxSplits: 1).map(String.init)
        guard comps.count == 2 else { return original }
        let folder = comps[0]
        let file = comps[1]
        for m in plan.merges where m.apply && m.aliases.contains(folder) {
            return root.appendingPathComponent(m.canonical).appendingPathComponent(file)
        }
        return original
    }

    /// Rewrite the artist-prefix portion of a filename when its parent
    /// folder gets renamed. Looks for `<oldArtist> - ` or `<oldArtist> — `
    /// at the start of the filename and substitutes the canonical name.
    /// Returns the original filename when no prefix match.
    private static func rewriteFilenamePrefix(_ filename: String, oldArtist: String, newArtist: String) -> String {
        let separators = [" - ", " — ", " – "]
        for sep in separators {
            let prefix = "\(oldArtist)\(sep)"
            if filename.hasPrefix(prefix) {
                let rest = String(filename.dropFirst(prefix.count))
                return "\(newArtist)\(sep)\(rest)"
            }
        }
        return filename
    }
}
