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

                // Word/char/line count
                HStack(spacing: 12) {
                    Text("\(doc.wordCount) words")
                    Text("\(doc.characterCount) chars")
                    Text("\(doc.lineCount) lines")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

                // Encoding
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
}
