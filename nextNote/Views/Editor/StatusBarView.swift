import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            if let index = appState.activeTabIndex {
                let doc = appState.openTabs[index].document

                // File type picker — click to change
                Menu {
                    ForEach(FileType.allCases) { type in
                        Button {
                            doc.fileType = type
                        } label: {
                            Label(type.displayName, systemImage: type.iconName)
                        }
                    }
                } label: {
                    Label(doc.fileType.displayName, systemImage: doc.fileType.iconName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                // Word/char/line count + reading-time estimate
                HStack(spacing: 12) {
                    Text("\(doc.wordCount) words")
                    Text("\(doc.characterCount) chars")
                    Text("\(doc.lineCount) lines")
                    Text(readingTimeLabel(words: doc.wordCount))
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

                // Backlinks pill (only meaningful for vault-backed notes;
                // BacklinksPill itself short-circuits if there's no vault path).
                BacklinksPill()

                // Modified indicator + encoding
                if appState.openTabs[index].isModified {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.tint)
                        .help("Unsaved changes")
                }
                Text("UTF-8")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 24)
        .background(Color(.secondarySystemBackground))
    }

    /// Words ÷ 200 wpm, rounded up to the nearest minute. Sub-minute reads
    /// show as "<1m" so the label width stays steady.
    private func readingTimeLabel(words: Int) -> String {
        let minutes = max(1, Int(ceil(Double(words) / 200.0)))
        if words < 200 { return "<1m" }
        return "\(minutes)m"
    }
}
