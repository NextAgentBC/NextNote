import SwiftUI

/// Shown when no project is open. Lists recent projects (click to open),
/// plus buttons to open an existing folder or start a fresh one. Replaces
/// the multi-row first-run setup that used to pick Notes/Media/Ebooks
/// separately.
struct WelcomeView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @State private var pickingError: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 280)
            Divider()
            detail
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 720, minHeight: 460)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "note.text")
                    .font(.title2)
                Text("NextNote")
                    .font(.title2.weight(.semibold))
            }
            .padding(20)

            Divider()

            if projectStore.recents.isEmpty {
                Spacer()
                Text("No recent projects")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(projectStore.recents) { entry in
                    RecentRow(entry: entry) {
                        if projectStore.openRecent(entry) == nil {
                            pickingError = "Couldn't open '\(entry.name)' — the folder may have moved."
                        }
                    } onRemove: {
                        projectStore.removeRecent(id: entry.id)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
                .listStyle(.sidebar)
            }
        }
        .background(.regularMaterial)
    }

    private var detail: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.tint)
                Text("Open a project")
                    .font(.title.weight(.semibold))
                Text("A project is one folder. NextNote will use it for notes, media, and ebooks.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            VStack(spacing: 10) {
                Button {
                    Task { _ = await projectStore.pick() }
                } label: {
                    Label("Open Existing Folder…", systemImage: "folder")
                        .frame(maxWidth: 240)
                }
                .keyboardShortcut("o", modifiers: .command)
                .controlSize(.large)

                Button {
                    Task { await createNewProject() }
                } label: {
                    Label("New Project…", systemImage: "plus")
                        .frame(maxWidth: 240)
                }
                .keyboardShortcut("n", modifiers: .command)
                .controlSize(.large)
            }

            if let pickingError {
                Text(pickingError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(40)
    }

    private func createNewProject() async {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.prompt = "Create Project"
        panel.message = "Pick a location for the new project folder."
        panel.nameFieldStringValue = "NextNote Project"
        let response = await panel.beginSheet()
        guard response == .OK, let url = panel.url else { return }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            _ = projectStore.open(url: url)
        } catch {
            pickingError = "Couldn't create folder: \(error.localizedDescription)"
        }
    }
}

private struct RecentRow: View {
    let entry: ProjectStore.RecentEntry
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(entry.pathHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Remove from Recents", role: .destructive) { onRemove() }
        }
    }
}

private extension NSSavePanel {
    func beginSheet() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { cont in
            self.begin { cont.resume(returning: $0) }
        }
    }
}
