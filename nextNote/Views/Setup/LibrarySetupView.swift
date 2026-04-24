import SwiftUI

// First-launch setup. Three rows — Notes / Media / Ebooks — with default
// paths pre-filled. User can Change per-row or accept defaults. Continue
// creates any missing folders and persists bookmarks. Shown until every
// root is resolved.
struct LibrarySetupView: View {
    @EnvironmentObject private var libraryRoots: LibraryRoots
    @State private var pendingPicks: [LibraryRoots.Kind: URL] = [:]
    @State private var error: String?
    @State private var seedPreset: Bool = true
    @State private var presetSummary: String?

    private func chosen(for kind: LibraryRoots.Kind) -> URL {
        pendingPicks[kind]
            ?? libraryRoots.url(for: kind)
            ?? libraryRoots.defaultURL(for: kind)
    }

    var body: some View {
        VStack(spacing: 22) {
            header
            VStack(spacing: 12) {
                ForEach(LibraryRoots.requiredKinds) { kind in
                    row(for: kind)
                }
            }
            .padding(.horizontal, 30)

            presetToggle
                .padding(.horizontal, 30)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 30)
            }

            if let presetSummary {
                Text(presetSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 30)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button("Use Defaults for All") { useDefaultsForAll() }
                    .buttonStyle(.bordered)
                Button("Start") { start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding(.bottom, 20)
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 420)
        .padding(.top, 30)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.2")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Welcome to nextNote")
                .font(.title2.bold())
            Text("Pick a folder for each library. Defaults live under \(friendlyParentPath).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
    }

    private var friendlyParentPath: String {
        let parent = LibraryRoots.defaultParent.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if parent.hasPrefix(home) {
            return "~" + parent.dropFirst(home.count)
        }
        return parent
    }

    @ViewBuilder
    private func row(for kind: LibraryRoots.Kind) -> some View {
        let url = chosen(for: kind)
        HStack(spacing: 14) {
            Image(systemName: kind.icon)
                .font(.system(size: 20))
                .frame(width: 32)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName)
                    .font(.system(size: 14, weight: .semibold))
                Text(friendly(url))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Change…") {
                Task { await pick(kind) }
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func friendly(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private var presetToggle: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: $seedPreset) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use AI Soul preset")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Seeds Notes root with Soul + skills + templates for Claude Code / Gemini CLI workflows. Won't overwrite existing files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            Spacer()
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Actions

    private func pick(_ kind: LibraryRoots.Kind) async {
        if let url = await libraryRoots.pick(kind: kind) {
            pendingPicks[kind] = url
        }
    }

    private func useDefaultsForAll() {
        for kind in LibraryRoots.requiredKinds {
            _ = libraryRoots.useDefault(kind: kind)
        }
    }

    private func start() {
        let fm = FileManager.default
        for kind in LibraryRoots.requiredKinds {
            if libraryRoots.url(for: kind) != nil { continue }
            let target = pendingPicks[kind] ?? libraryRoots.defaultURL(for: kind)
            do {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } catch {
                self.error = "Could not create \(kind.displayName) folder: \(error.localizedDescription)"
                return
            }
            if pendingPicks[kind] == nil {
                _ = libraryRoots.useDefault(kind: kind)
            }
        }
        self.error = nil

        if seedPreset, let notesRoot = libraryRoots.url(for: .notes) {
            do {
                let report = try VaultPresetSeeder.seed(into: notesRoot)
                presetSummary = describe(report)
            } catch {
                self.error = "Preset seeding failed: \(error.localizedDescription)"
            }
        }
    }

    private func describe(_ report: VaultPresetSeeder.Report) -> String {
        var parts: [String] = []
        if !report.copied.isEmpty {
            parts.append("Copied \(report.copied.count) files")
        }
        if !report.skipped.isEmpty {
            parts.append("Kept \(report.skipped.count) existing (identical)")
        }
        if !report.conflicts.isEmpty {
            parts.append("Skipped \(report.conflicts.count) that differ — see Notes root")
        }
        if parts.isEmpty { return "Preset already applied." }
        return "AI Soul preset applied: " + parts.joined(separator: ", ") + "."
    }
}
