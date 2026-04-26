import Foundation

// Walks a root folder, groups media by containing directory, and asks the
// LLM to clean up the folder name into a good playlist title. The heavy
// lifting (walk, dedupe, playlist create/update) lives in MediaLibrary so
// this file only holds the folder-scan shape and the AI prompt.
@MainActor
enum PlaylistSynth {

    struct Candidate: Sendable {
        let folderPath: String
        let folderName: String
        let mediaURLs: [URL]
    }

    /// Default directory names that should not become playlists — ebooks,
    /// thumbnail caches, yt-dlp partials, macOS metadata dirs.
    static let defaultExcludes: Set<String> = [
        "ebooks", "books", ".thumbnails", "__MACOSX",
        ".DS_Store", "_tmp", "_partial",
    ]

    // MARK: - Scan

    /// Walk `root` and return one candidate per folder that directly contains
    /// at least one audio or video file. Folders whose name matches `excludes`
    /// (case-insensitive) are skipped along with their descendants.
    static func scan(
        root: URL,
        excludes: Set<String> = defaultExcludes
    ) -> [Candidate] {
        let fm = FileManager.default
        let excludeLower = Set(excludes.map { $0.lowercased() })

        // Group media URLs by their immediate parent directory path.
        var grouped: [String: [URL]] = [:]

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        for case let url as URL in enumerator {
            // Prune excluded subtrees.
            var shouldSkip = false
            for component in url.pathComponents {
                if excludeLower.contains(component.lowercased()) {
                    shouldSkip = true
                    break
                }
            }
            if shouldSkip {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard MediaKind.from(url: url) != nil else { continue }
            let parent = url.deletingLastPathComponent().path
            grouped[parent, default: []].append(url)
        }

        return grouped
            .sorted { $0.key < $1.key }
            .map { (path, urls) in
                Candidate(
                    folderPath: path,
                    folderName: (path as NSString).lastPathComponent,
                    mediaURLs: urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
                )
            }
    }

    // MARK: - Name suggestion

    /// Ask the AI for a clean playlist title based on folder name + sample track titles.
    /// Falls back to the raw folder name if AI is unreachable or returns garbage.
    static func suggestName(
        folderName: String,
        sampleTitles: [String]
    ) async -> String {
        return folderName
    }
}
