import SwiftUI

#if os(macOS)
/// Settings → Media tab. Single home for media-related paths + behavior
/// toggles previously scattered across the Library menu, Media menu, and
/// AI settings (yt-dlp download folder).
struct MediaSettingsView: View {
    @EnvironmentObject private var libraryRoots: LibraryRoots
    @StateObject private var mediaLibrary = MediaLibrary.shared
    @StateObject private var locator = YTDLPLocator.shared

    @AppStorage("media.autoOrganizeOnYTDownload") private var autoOrgYT: Bool = true
    @AppStorage("media.autoOrganizeOnDrop") private var autoOrgDrop: Bool = true

    var body: some View {
        Form {
            Section {
                pathRow(
                    label: "Media library root",
                    help: "Where AI Organize moves files into <Artist>/ folders. Drag-drop targets land here.",
                    url: libraryRoots.mediaRoot,
                    pick: { Task { await libraryRoots.pick(kind: .media) } },
                    reveal: { FinderActions.reveal(libraryRoots.mediaRoot) }
                )
                pathRow(
                    label: "Ambient folder",
                    help: "Background music library — scanned for the ambient player. Independent of the media library root.",
                    url: mediaLibrary.ambientFolderURL,
                    pick: { Task { _ = await mediaLibrary.pickAmbientFolder() } },
                    reveal: { FinderActions.reveal(mediaLibrary.ambientFolderURL) }
                )
                pathRow(
                    label: "YouTube download folder",
                    help: "yt-dlp writes raw downloads here before AI Organize moves them.",
                    url: locator.downloadFolderURL,
                    pick: { Task { await locator.pickDownloadFolder() } },
                    reveal: { FinderActions.reveal(locator.downloadFolderURL) }
                )
            } header: {
                Text("Folders")
            }

            Section {
                Toggle("Auto-organize after YouTube download", isOn: $autoOrgYT)
                    .help("After yt-dlp finishes, AI extracts artist + song and moves the file into <Media>/<Artist>/.")
                Toggle("Auto-organize on drag-drop", isOn: $autoOrgDrop)
                    .help("Files dropped onto the ambient bar run through AI Organize before joining the library.")
            } header: {
                Text("Behavior")
            }

            Section {
                pathRow(
                    label: "yt-dlp binary",
                    help: "Required for YouTube downloads + Restore Titles.",
                    url: locator.binaryURL,
                    pick: { Task { await locator.pickBinary() } },
                    reveal: { FinderActions.reveal(locator.binaryURL) }
                )
                pathRow(
                    label: "ffmpeg binary",
                    help: "Optional. Enables 1080p+ merges + transcoding for VP9/AV1 → HEVC.",
                    url: locator.ffmpegURL,
                    pick: { Task { await locator.pickFFmpeg() } },
                    reveal: { FinderActions.reveal(locator.ffmpegURL) }
                )
            } header: {
                Text("Tools")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func pathRow(
        label: String,
        help: String,
        url: URL?,
        pick: @escaping () -> Void,
        reveal: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.body.weight(.medium))
                Spacer()
                Button("Choose…") { pick() }
                Button {
                    reveal()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .disabled(url == nil)
                .help("Reveal in Finder")
            }
            Text(url?.path ?? "Not set")
                .font(.caption)
                .foregroundStyle(url == nil ? .red : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(help)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
#endif
