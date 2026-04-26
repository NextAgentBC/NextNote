import SwiftUI

extension MediaLibraryView {
    var sidebar: some View {
        VStack(spacing: 0) {
            libraryActionsBar
            Divider()
            sidebarList
            if isGeneratingPlaylists || !playlistGenStatus.isEmpty {
                statusBar(
                    isActive: isGeneratingPlaylists,
                    status: playlistGenStatus,
                    onClear: { playlistGenStatus = "" }
                )
            }
            if isBackfilling || !backfillStatus.isEmpty {
                statusBar(
                    isActive: isBackfilling,
                    status: backfillStatus,
                    onClear: { backfillStatus = "" }
                )
            }
            if isAutoCleaning || !autoCleanStatus.isEmpty {
                statusBar(
                    isActive: isAutoCleaning,
                    status: autoCleanStatus,
                    onClear: { autoCleanStatus = "" }
                )
            }
            Divider()
            nowPlayingVibe
        }
    }

    var sidebarList: some View {
        List(selection: $selectedPlaylistID) {
            Section("Library") {
                HStack {
                    Image(systemName: "music.note")
                    Text("All Tracks")
                    Spacer()
                    Text("\(library.tracks.count)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .tag(UUID?.none)
            }

            Section {
                ForEach(library.playlists) { p in
                    HStack {
                        Image(systemName: "music.note.list")
                        Text(p.name)
                        Spacer()
                        Text("\(p.trackIDs.count)")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .tag(UUID?.some(p.id))
                    .contextMenu {
                        Button("Rename") {
                            renameText = p.name
                            renameTarget = p
                        }
                        Button("Play") {
                            player.setQueue(library.tracks(in: p))
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            library.deletePlaylist(id: p.id)
                            if selectedPlaylistID == p.id {
                                selectedPlaylistID = nil
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Playlists")
                    Spacer()
                    Button {
                        generatePlaylistsFromFolders()
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .buttonStyle(.borderless)
                    .help("AI: Generate playlists from the ambient folder tree")
                    .disabled(isGeneratingPlaylists || library.ambientFolderURL == nil)

                    Button {
                        newPlaylistName = ""
                        showingNewPlaylist = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// Single-line live status row used by the three long-running sidebar
    /// jobs (playlist gen, backfill, auto-clean). Shows a spinner when
    /// active and a dismiss button when done.
    private func statusBar(
        isActive: Bool,
        status: String,
        onClear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            if isActive { ProgressView().controlSize(.small) }
            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if !isActive {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
