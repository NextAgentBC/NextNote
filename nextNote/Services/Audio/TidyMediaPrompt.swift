import Foundation

/// Prompt template fed to Claude CLI from the embedded terminal when the
/// user clicks "Tidy with Claude" in the Media Library. Bakes in the
/// nextNote layout convention so Claude lands files where the rest of
/// the app expects them.
///
/// The prompt is deliberately tight: tell Claude what to do, what the
/// constraints are, and to *show the plan and wait for confirmation*
/// before any moves. We don't want a one-shot autonomous file shuffler.
enum TidyMediaPrompt {
    static func build(rootPath: String) -> String {
        """
        Help me tidy up my music / video library at:

            \(rootPath)

        Goal layout: <root>/<Artist>/<Artist> - <Song>.<ext>

        Idempotent: this command may be re-run as the library grows. Files
        already at the goal layout MUST be left alone — don't propose any
        moves for them. Only files that don't match get rewritten.

        Rules:
        1. Walk every audio + video file under the root recursively.
        0. Skip any file whose path already matches the goal layout
           (parent dir = artist, filename starts with "<artist> - ", no
           [videoId] suffix). Don't print these in the plan; just count
           them at the end as "N already canonical".
        2. Parse each filename into (artist, song). Patterns to handle:
           - "Artist - Song", "Artist – Song", "Artist — Song", "Artist | Song"
           - Strip trailing yt-dlp video id like " [dQw4w9WgXcQ]"
             (11-char base64-ish in square brackets right before extension).
           - Strip marketing tags: "(Official Music Video)", "[HD]", "[4K]",
             "(Lyric Video)", "(Audio)", " | Official Audio", etc.
           - Keep "(feat. …)" and similar real-collab markers.
        3. If a file has no separator, infer artist from the immediate
           parent folder name when reasonable (e.g. file already lives
           under <root>/Coldplay/ → artist = "Coldplay").
        4. Reuse existing artist folder names case-insensitively. If
           "邓紫棋" already exists, route a new "G.E.M." track there.
           Prefer the native-script form when both exist.
        5. Sanitize filenames: strip / : \\ * ? " < > | and leading dots.
           Keep Chinese / Japanese / Korean characters intact.
        6. Detect duplicates (same artist + song, possibly different
           extension or noise) — flag them, don't silently overwrite.
        7. Ignore hidden files, .DS_Store, and any file under a folder
           starting with ".".

        Process:
        - First, scan the tree and PRINT a rename plan as a table:
            current relative path → new relative path
        - Group by artist folder. Show counts.
        - Flag duplicates and any files where you couldn't infer artist.
        - Wait for me to type "go" before moving any files.
        - When I confirm, do the moves with `mv`, creating folders as
          needed. Print one line per move. Stop on first error.
        """
    }
}
