import SwiftUI

/// Single source of truth for the per-track right-click menu. Every surface
/// that shows a track row (sidebar, AmbientBar queue popover, MediaLibrary
/// table) calls this so the action set stays identical.
@MainActor
@ViewBuilder
func trackContextMenu(
    track: Track,
    onRenameTitle: (() -> Void)? = nil,
    onRenameFile: (() -> Void)? = nil,
    onRemove: (() -> Void)? = nil,
    onTrash: (() -> Void)? = nil,
    onAddToAssets: (() -> Void)? = nil
) -> some View {
    Button("Play") { MediaPlayback.play([track]) }
    Button("Enqueue") { MediaPlayback.enqueue([track]) }
    Divider()
    if let onRenameTitle {
        Button("Rename Title…") { onRenameTitle() }
    }
    if let onRenameFile {
        Button("Rename File on Disk…") { onRenameFile() }
    }
    if onRenameTitle != nil || onRenameFile != nil {
        Divider()
    }
    if let onAddToAssets {
        Button("Add to Assets") { onAddToAssets() }
        Divider()
    }
    Button("Reveal in Finder") { FinderActions.reveal([track.url]) }
    if let onRemove {
        Divider()
        Button("Remove from Library") { onRemove() }
    }
    if let onTrash {
        Button("Move to Trash", role: .destructive) { onTrash() }
    }
}
