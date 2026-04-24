import SwiftUI

// First-launch setup. Three rows — Notes / Media / Ebooks — with default
// paths pre-filled. User can Change per-row or accept defaults. Continue
// creates any missing folders and persists bookmarks. Shown until every
// root is resolved.
struct LibrarySetupView: View {
    @EnvironmentObject private var libraryRoots: LibraryRoots
    @State private var pendingPicks: [LibraryRoots.Kind: URL] = [:]
    @State private var error: String?

    private func chosen(for kind: LibraryRoots.Kind) -> URL {
        pendingPicks[kind]
            ?? libraryRoots.url(for: kind)
            ?? libraryRoots.defaultURL(for: kind)
    }

    var body: some View {
        VStack(spacing: 22) {
            header
            VStack(spacing: 12) {
                ForEach(LibraryRoots.Kind.allCases) { kind in
                    row(for: kind)
                }
            }
            .padding(.horizontal, 30)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 30)
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

    // MARK: - Actions

    private func pick(_ kind: LibraryRoots.Kind) async {
        if let url = await libraryRoots.pick(kind: kind) {
            pendingPicks[kind] = url
        }
    }

    private func useDefaultsForAll() {
        for kind in LibraryRoots.Kind.allCases {
            _ = libraryRoots.useDefault(kind: kind)
        }
    }

    private func start() {
        let fm = FileManager.default
        for kind in LibraryRoots.Kind.allCases {
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
    }
}
