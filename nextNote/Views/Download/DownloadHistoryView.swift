import SwiftUI
import SwiftData

/// History of YouTube downloads. Live view backed by SwiftData — rows
/// update as the coordinator persists progress changes.
struct DownloadHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var libraryRoots: LibraryRoots
    @StateObject private var library = MediaLibrary.shared
    @StateObject private var player = AmbientPlayer.shared

    @Query(sort: \DownloadJob.createdAt, order: .reverse) private var jobs: [DownloadJob]
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case active = "Active"
        case done = "Done"
        case failed = "Failed"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filteredJobs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredJobs) { job in
                            row(job)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("Downloads")
                .font(.title2.bold())
            Text("\(jobs.count)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Picker("", selection: $filter) {
                ForEach(Filter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .labelsHidden()

            Button("Clear Done") {
                clearDone()
            }
            .disabled(!hasDone)

            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(filter == .all
                 ? "No downloads yet."
                 : "No \(filter.rawValue.lowercased()) downloads.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Row

    @ViewBuilder
    private func row(_ job: DownloadJob) -> some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon(job.status)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(job.title ?? job.sourceURL)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    if let uploader = job.uploader {
                        Text(uploader)
                            .foregroundStyle(.secondary)
                    }
                    Text("·").foregroundStyle(.tertiary)
                    Text(job.mode == .audio ? "Audio" : "Video")
                        .foregroundStyle(.secondary)
                    if !job.qualityRaw.isEmpty && job.mode == .video {
                        Text("·").foregroundStyle(.tertiary)
                        Text(job.qualityRaw)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(job.createdAt, style: .relative)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)

                if job.status == .downloading || job.status == .transcoding {
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                    Text(job.statusLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let err = job.errorMessage, job.status == .failed {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                } else if job.status == .done {
                    if let path = job.finalPath {
                        Text(path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            actions(job)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func statusIcon(_ s: DownloadJob.Status) -> some View {
        switch s {
        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .downloading, .transcoding:
            ProgressView()
                .controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .canceled:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func actions(_ job: DownloadJob) -> some View {
        VStack(spacing: 6) {
            switch job.status {
            case .downloading, .transcoding, .queued:
                Button {
                    DownloadJobCoordinator.shared.cancel(job.id, modelContext: modelContext)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Cancel")
            case .failed, .canceled:
                Button {
                    DownloadJobCoordinator.shared.retry(
                        job.id,
                        modelContext: modelContext,
                        libraryRoots: libraryRoots,
                        appState: appState,
                        library: library,
                        player: player
                    )
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)
                .help("Retry")
            case .done:
                if let url = job.finalURL {
                    Button {
                        FinderActions.reveal(url)
                    } label: {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal in Finder")
                }
            }

            Button {
                DownloadJobCoordinator.shared.delete(job.id, modelContext: modelContext)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .help("Remove from history")
        }
        .padding(.top, 2)
    }

    // MARK: - Filter / actions

    private var filteredJobs: [DownloadJob] {
        switch filter {
        case .all: return jobs
        case .active: return jobs.filter { $0.status == .downloading || $0.status == .transcoding || $0.status == .queued }
        case .done: return jobs.filter { $0.status == .done }
        case .failed: return jobs.filter { $0.status == .failed || $0.status == .canceled }
        }
    }

    private var hasDone: Bool {
        jobs.contains { $0.status == .done }
    }

    private func clearDone() {
        for job in jobs where job.status == .done {
            modelContext.delete(job)
        }
        try? modelContext.save()
    }
}
