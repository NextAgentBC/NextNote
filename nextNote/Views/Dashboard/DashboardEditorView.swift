import SwiftUI

// Split view for `_dashboard.md`. Top half: pinned user region, editable
// through a standard EditorView. Bottom half: AI region, rendered read-only
// via MarkdownPreviewView with a "Regenerate" button. Saving re-serializes
// both halves with the marker format.
//
// R3 leaves Regenerate as a stub — R5 wires it into DashboardService.
struct DashboardEditorView: View {
    /// Relative path of the _dashboard.md inside the vault.
    let relativePath: String
    /// The parent folder's relative path ("" for root) — used by R5 when
    /// wiring Regenerate to the DashboardService.
    let folderRelativePath: String

    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var appState: AppState

    @State private var parsed = DashboardDocument.Parsed(pinned: "", ai: "", aiGeneratedAt: nil, aiInputHash: nil, fallbackToPinned: false)
    @State private var pinnedBuffer: String = ""
    @State private var loadedFromPath: String?
    @State private var regenerating = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pinnedPane
                .frame(maxHeight: .infinity)
            Divider()
            aiPane
                .frame(maxHeight: .infinity)
        }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: relativePath) { _, _ in loadIfNeeded() }
        .onChange(of: pinnedBuffer) { _, new in
            // Mark dirty so the save loop in ContentView picks this up.
            if let idx = appState.activeTabIndex {
                appState.openTabs[idx].isModified = true
                appState.openTabs[idx].document.content = DashboardDocument.serialize(
                    pinned: new,
                    ai: parsed.ai,
                    aiInputHash: parsed.aiInputHash ?? "",
                    at: parsed.aiGeneratedAt ?? Date()
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label(relativePath, systemImage: "chart.bar.doc.horizontal")
                .font(.headline)
            Spacer()
            if let gen = parsed.aiGeneratedAt {
                Text("AI generated \(gen.formatted(.relative(presentation: .numeric)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !parsed.ai.isEmpty {
                Text("AI content present")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No AI content yet")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button {
                Task { await regenerate() }
            } label: {
                Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(regenerating)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor))
    }

    private var pinnedPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pinned (your notes)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 4)
            TextEditor(text: $pinnedBuffer)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private var aiPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI (read-only, regenerated from children)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 4)
            if parsed.ai.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Nothing yet. Click Regenerate to summarize this folder's contents.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MarkdownPreviewView(content: parsed.ai)
            }
        }
    }

    // MARK: - Load / save

    private func loadIfNeeded() {
        guard loadedFromPath != relativePath, let url = vault.url(for: relativePath) else { return }
        let raw = (try? NoteIO.read(url: url)) ?? ""
        parsed = DashboardDocument.parse(raw)
        pinnedBuffer = parsed.pinned
        loadedFromPath = relativePath
    }

    // Stub — R5 implementation replaces this body with a call to
    // DashboardService.regenerate(folder:)
    private func regenerate() async {
        regenerating = true
        defer { regenerating = false }
        await DashboardService.shared.regenerate(folderRelativePath: folderRelativePath, dashboardRelativePath: relativePath)
        loadedFromPath = nil
        loadIfNeeded()
    }
}
