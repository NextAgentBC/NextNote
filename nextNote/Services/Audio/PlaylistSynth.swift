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

    // MARK: - AI name suggestion

    /// Ask the LLM to promote a raw folder name into a clean playlist title.
    /// Returns the folder name unchanged on any parse failure / timeout —
    /// playlist generation must never hard-fail because the model hangs.
    static func suggestName(folderName: String, sampleTitles: [String]) async -> String {
        let system = LLMMessage(.system, """
        You rename raw folder names into clean playlist titles. Strict JSON only:
        {"name": "<playlist title>"}

        Rules:
        - Expand obvious abbreviations (MJ → Michael Jackson, BTS → BTS, lofi → Lo-Fi).
        - Use natural title case. No quotes, no punctuation at the ends.
        - If the folder name already looks clean, return it as-is.
        - Keep under 40 characters.
        - ASCII where possible.
        """)
        let sample = sampleTitles.prefix(5).joined(separator: "\n- ")
        let user = LLMMessage(.user, """
        Folder: \(folderName)
        Sample files:
        - \(sample)
        """)

        // Race a detached timeout task against the LLM call so a hung remote
        // doesn't freeze the whole batch. If the deadline wins, we cancel
        // the LLM task (URLSession honors cancellation) and fall back to the
        // raw folder name.
        let provider = AITextService.shared.currentProvider
        let llmTask = Task { @MainActor () -> String? in
            do {
                let raw = try await provider.generate(
                    messages: [system, user],
                    parameters: LLMParameters(maxTokens: 80, temperature: 0.2)
                )
                return Self.parseName(from: raw)
            } catch {
                NSLog("[PlaylistSynth] AI error for '\(folderName)': \(error.localizedDescription)")
                return nil
            }
        }
        let deadline = Task.detached {
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            llmTask.cancel()
        }
        let parsed = await llmTask.value
        deadline.cancel()
        if let parsed, !parsed.isEmpty { return parsed }
        return folderName
    }

    nonisolated private static func parseName(from raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let nl = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: nl)...])
            }
            if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = s.firstIndex(of: "{"),
              let end = s.lastIndex(of: "}"),
              start < end else { return nil }
        let slice = String(s[start...end])
        guard let data = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = obj["name"] as? String
        else { return nil }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(60))
    }
}
