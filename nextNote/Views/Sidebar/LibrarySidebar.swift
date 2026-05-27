import SwiftUI

/// Sidebar shell. Two sections, top-down:
///   1. `NotesSection` — the unified file tree (vault Notes/Assets/Media/Ebooks
///      all live under one folder hierarchy now; the old per-type "tray" UI
///      was removed in 0.4.0).
///   2. `PinnedFoldersSection` — user-pinned external folders, hidden when
///      none are pinned (so the sidebar looks identical for users who don't
///      use that feature).
struct LibrarySidebar: View {
    var body: some View {
        VStack(spacing: 0) {
            NotesSection()
                .frame(maxHeight: .infinity)
            PinnedFoldersSection()
        }
    }
}
