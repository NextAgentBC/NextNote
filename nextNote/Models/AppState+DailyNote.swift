import Foundation

extension AppState {
    /// Open today's daily note at `<vault>/Daily/YYYY-MM-DD.md`. Creates the
    /// folder and seed file (with a date heading) on first call for the day;
    /// otherwise just opens the existing tab. Wired to File > Daily Note (⇧⌘T).
    @MainActor
    func openDailyNote(vault: VaultStore) async {
        guard let root = vault.root else {
            lastSaveError = "Choose a vault before creating a daily note."
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let dateStr = formatter.string(from: Date())

        let folderName = "Daily"
        let relPath = "\(folderName)/\(dateStr).md"
        let absoluteURL = root.appending(path: relPath, directoryHint: .notDirectory)

        if FileManager.default.fileExists(atPath: absoluteURL.path) {
            let content = (try? String(contentsOf: absoluteURL, encoding: .utf8)) ?? ""
            openVaultFile(relativePath: relPath) {
                TextDocument(title: dateStr, content: content, fileType: .md)
            }
            selectedSidebarPath = relPath
            return
        }

        do {
            // Create the Daily folder if it isn't already there. We swallow
            // "exists" errors so a partial run doesn't block the create-note
            // step below.
            if !FileManager.default.fileExists(atPath: root.appending(path: folderName, directoryHint: .isDirectory).path) {
                _ = try await vault.createFolder(inParent: "", name: folderName)
            }
            let header = "# \(dateStr)\n\n"
            let newPath = try await vault.createNote(
                inFolder: folderName,
                title: dateStr,
                initialContent: header
            )
            openVaultFile(relativePath: newPath) {
                TextDocument(title: dateStr, content: header, fileType: .md)
            }
            selectedSidebarPath = newPath
        } catch {
            lastSaveError = "Daily note failed: \(error.localizedDescription)"
        }
    }
}
