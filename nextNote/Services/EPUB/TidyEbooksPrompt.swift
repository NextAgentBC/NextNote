import Foundation

/// Prompt template for the embedded Claude CLI when the user hits
/// "Tidy with Claude" in the Ebooks tray. Asks Claude to walk the
/// ebooks root and route loose .epub / .pdf files into the user's
/// existing subfolders — without renaming files or re-organizing
/// books that are already inside a folder.
enum TidyEbooksPrompt {
    static func build(rootPath: String) -> String {
        """
        Help me tidy up my ebooks library at:

            \(rootPath)

        Layout: <root>/<Folder>/<book>.epub  (or .pdf)

        I have already created subfolders inside <root>. New books I
        download land at the root level. Your job is to route those
        loose files into the right existing subfolder, without
        renaming files or touching books already inside a folder.

        Idempotent: this command may be re-run as the library grows.
        Files already in any subfolder MUST be left alone — don't
        propose any moves for them.

        Rules:
        1. List the immediate subfolders of <root> (depth 1). Don't
           invent new folders. If a book doesn't fit any existing
           folder, leave it at root and flag it in the report.
        2. Walk every file at the root level (not inside subfolders)
           with extension .epub, .pdf, .mobi, or .azw3.
        3. For each loose file, match against the existing subfolder
           names using the filename / title cues. Be smart about it:
              - "AP_Calculus_Premium_2026.epub" → "Ap" folder
              - "Princeton_AP_Computer_Science.epub" → "Ap"
              - "中国古代算命术.epub" → "杂书" if no better match
              - "Atomic_Habits.epub" → "杂书" (general non-fiction)
           Use Chinese folder names when the book's primary script is
           Chinese; English when English. Match case-insensitively.
        4. Don't rename the file — just move it.
        5. Conservative: when in doubt, leave at root and ask. False
           positives are worse than false negatives here.
        6. Ignore hidden files, .DS_Store, and anything inside hidden
           directories.

        Process:
        - PRINT a routing plan as a table:
            current filename → target subfolder
          Group by target folder. Show counts per folder. List any
          file you couldn't place under "Unrouted — needs human".
        - Wait for me to type "go" before moving any files.
        - When I confirm, do the moves with `mv`. Print one line per
          move. Stop on first error.
        """
    }
}
