import SwiftUI

#if os(macOS)
/// Review sheet for AI-proposed library reconciliation. Two sections:
///   1. Artist folder merges (alias → canonical)
///   2. Duplicate track sets (same artist + song)
/// User toggles individual rows + picks which file to keep, then Apply
/// runs `LibraryReconciler.apply` and closes.
struct LibraryReconcileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var libraryRoots: LibraryRoots
    @StateObject private var library = MediaLibrary.shared
    @EnvironmentObject private var appState: AppState

    @State private var phase: Phase = .planning
    @State private var plan: LibraryReconciler.Plan = .init(
        deadTracks: [], duplicateLibraryRecords: [], emptyFolders: [],
        merges: [], duplicates: []
    )
    @State private var status: String = "Scanning library…"
    @State private var error: String?
    @State private var outcome: LibraryReconciler.Outcome?

    enum Phase { case planning, review, applying, done, error }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 480)
        .task { await runPlan() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reconcile Library")
                    .font(.title2.bold())
                Text("AI groups duplicate artist folders and detects duplicate songs. Review before applying.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if phase == .applying || phase == .planning {
                ProgressView().controlSize(.small)
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .planning:
            VStack {
                Spacer()
                ProgressView().controlSize(.small)
                Text(status).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .review:
            if plan.isEmpty {
                emptyReview
            } else {
                reviewList
            }
        case .applying:
            VStack {
                Spacer()
                ProgressView()
                Text(status).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .done:
            doneSummary
        case .error:
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text(error ?? "Something went wrong.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyReview: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal").font(.system(size: 32)).foregroundStyle(.green)
            Text("Library is clean.")
                .font(.headline)
            Text("AI found no duplicate artists or songs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reviewList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !plan.deadTracks.isEmpty {
                    sectionHeader("Dead tracks (\(plan.deadTracks.count))")
                    ForEach(plan.deadTracks.indices, id: \.self) { idx in
                        deadRow(idx)
                    }
                }
                if !plan.duplicateLibraryRecords.isEmpty {
                    sectionHeader("Duplicate library records (\(plan.duplicateLibraryRecords.count))")
                    ForEach(plan.duplicateLibraryRecords.indices, id: \.self) { idx in
                        libDupRow(idx)
                    }
                }
                if !plan.emptyFolders.isEmpty {
                    sectionHeader("Empty folders (\(plan.emptyFolders.count))")
                    ForEach(plan.emptyFolders.indices, id: \.self) { idx in
                        emptyFolderRow(idx)
                    }
                }
                if !plan.merges.isEmpty {
                    sectionHeader("Artist folder merges (\(plan.merges.count))")
                    ForEach(plan.merges.indices, id: \.self) { idx in
                        mergeRow(idx)
                    }
                }
                if !plan.duplicates.isEmpty {
                    sectionHeader("Duplicate songs (\(plan.duplicates.count))")
                    ForEach(plan.duplicates.indices, id: \.self) { idx in
                        duplicateRow(idx)
                    }
                }
            }
            .padding(14)
        }
    }

    private func deadRow(_ idx: Int) -> some View {
        let entry = plan.deadTracks[idx]
        return HStack {
            Toggle("", isOn: Binding(
                get: { plan.deadTracks[idx].apply },
                set: { plan.deadTracks[idx].apply = $0 }
            ))
            .labelsHidden()
            Image(systemName: "questionmark.folder").foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.body.weight(.medium))
                Text(entry.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("File missing on disk. Remove the library entry only.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func emptyFolderRow(_ idx: Int) -> some View {
        let entry = plan.emptyFolders[idx]
        return HStack {
            Toggle("", isOn: Binding(
                get: { plan.emptyFolders[idx].apply },
                set: { plan.emptyFolders[idx].apply = $0 }
            ))
            .labelsHidden()
            Image(systemName: "folder.badge.minus").foregroundStyle(.gray)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.body.weight(.medium))
                Text("No media files. Folder will be removed.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func libDupRow(_ idx: Int) -> some View {
        let entry = plan.duplicateLibraryRecords[idx]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { plan.duplicateLibraryRecords[idx].apply },
                    set: { plan.duplicateLibraryRecords[idx].apply = $0 }
                ))
                .labelsHidden()
                Image(systemName: "doc.badge.plus").foregroundStyle(.purple)
                Text(entry.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(entry.titles.count) records")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(entry.titles.enumerated()), id: \.offset) { i, title in
                HStack(spacing: 6) {
                    Image(systemName: i == entry.keepIndex ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(i == entry.keepIndex ? Color.accentColor : .secondary)
                        .onTapGesture { plan.duplicateLibraryRecords[idx].keepIndex = i }
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(i == entry.keepIndex ? .primary : .secondary)
                        .strikethrough(i != entry.keepIndex)
                    Spacer()
                }
                .padding(.leading, 26)
            }
            Text("Same file referenced multiple times. Drop extras (file stays).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 26)
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .padding(.bottom, 2)
    }

    private func mergeRow(_ idx: Int) -> some View {
        let merge = plan.merges[idx]
        let isRename = merge.aliases.count == 1
        return HStack(alignment: .top) {
            Toggle("", isOn: Binding(
                get: { plan.merges[idx].apply },
                set: { plan.merges[idx].apply = $0 }
            ))
            .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: isRename ? "pencil" : "folder.fill")
                        .foregroundStyle(isRename ? Color.purple : .blue)
                    Text(merge.canonical).font(.body.weight(.medium))
                    Text("←").foregroundStyle(.secondary)
                    Text(merge.aliases.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(isRename
                     ? "Rename folder to \(merge.canonical) and rewrite filename prefixes."
                     : "Merge \(merge.aliases.count) folder(s) into \(merge.canonical), rewrite filenames, delete empties.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func duplicateRow(_ idx: Int) -> some View {
        let dup = plan.duplicates[idx]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { plan.duplicates[idx].apply },
                    set: { plan.duplicates[idx].apply = $0 }
                ))
                .labelsHidden()
                Image(systemName: "doc.on.doc").foregroundStyle(.orange)
                Text("\(dup.artist) — \(dup.song)").font(.body.weight(.medium))
                Spacer()
                Text("\(dup.relativePaths.count) copies")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(dup.relativePaths.enumerated()), id: \.offset) { i, rel in
                HStack(spacing: 6) {
                    Image(systemName: i == dup.keepIndex ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(i == dup.keepIndex ? Color.accentColor : .secondary)
                        .onTapGesture { plan.duplicates[idx].keepIndex = i }
                    Text(rel)
                        .font(.caption.monospaced())
                        .foregroundStyle(i == dup.keepIndex ? .primary : .secondary)
                        .strikethrough(i != dup.keepIndex)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.leading, 26)
            }
            Text("Keeper stays. Others move to Trash.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 26)
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }

    private var doneSummary: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            if let o = outcome {
                Text("Reconcile complete").font(.headline)
                Text("Dead: \(o.deadPruned) · LibDup: \(o.libDupsPruned) · Empty: \(o.emptyFoldersRemoved) · Merge: \(o.foldersMerged) · Rename: \(o.foldersRenamed) · Moved: \(o.filesMoved) · Renamed files: \(o.filesRenamed) · Trashed: \(o.filesTrashed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !o.failed.isEmpty {
                    Text("\(o.failed.count) failed").font(.caption).foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if phase == .review && !plan.isEmpty {
                Text(selectionSummary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(phase == .applying)

            switch phase {
            case .review where !plan.isEmpty:
                Button("Apply") { Task { await runApply() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .done:
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .error, .review:
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
            default:
                EmptyView()
            }
        }
        .padding(12)
    }

    private var selectionSummary: String {
        let dt = plan.deadTracks.filter(\.apply).count
        let ld = plan.duplicateLibraryRecords.filter(\.apply).count
        let ef = plan.emptyFolders.filter(\.apply).count
        let m = plan.merges.filter(\.apply).count
        let d = plan.duplicates.filter(\.apply).count
        return "Dead: \(dt) · LibDup: \(ld) · Empty: \(ef) · Merge: \(m) · Dup: \(d)"
    }

    // MARK: - Actions

    private func runPlan() async {
        guard let root = libraryRoots.mediaRoot else {
            error = "Media library root is not configured."
            phase = .error
            return
        }
        phase = .planning
        status = "AI scanning artists + tracks…"
        do {
            let p = try await LibraryReconciler.plan(underRoot: root, library: library)
            plan = p
            phase = .review
        } catch {
            self.error = error.localizedDescription
            phase = .error
        }
    }

    private func runApply() async {
        guard let root = libraryRoots.mediaRoot else { return }
        phase = .applying
        status = "Applying…"
        let o = await LibraryReconciler.apply(plan, underRoot: root, library: library) { line in
            status = line
        }
        outcome = o
        phase = .done
        // Trigger a media rescan so the sidebar reflects the new layout.
        appState.triggerRescanMedia = true
    }
}
#endif
