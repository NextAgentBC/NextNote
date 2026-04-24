import SwiftUI

struct TabBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(appState.openTabs) { tab in
                        TabItemView(tab: tab, isActive: tab.id == appState.activeTabId)
                            .id(tab.id)
                            .onTapGesture {
                                appState.activeTabId = tab.id
                            }
                            .contextMenu {
                                Button("Close") {
                                    appState.closeTab(id: tab.id)
                                }
                                Button("Close Others") {
                                    appState.closeOtherTabs(except: tab.id)
                                }
                                Divider()
                                if tab.isModified {
                                    Button("Save") {
                                        saveTab(tab)
                                    }
                                }
                            }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 36)
            .background(Color(.secondarySystemBackground))
            .onChange(of: appState.activeTabId) { _, newId in
                if let id = newId {
                    withAnimation {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private func saveTab(_ tab: TabItem) {
        if let index = appState.openTabs.firstIndex(where: { $0.id == tab.id }) {
            appState.openTabs[index].isModified = false
        }
    }
}

struct TabItemView: View {
    let tab: TabItem
    let isActive: Bool
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.bookID != nil ? "book.closed" : tab.document.fileType.iconName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(tab.bookTitle ?? tab.document.title)
                .font(.system(size: 12))
                .lineLimit(1)

            if tab.isModified {
                Circle()
                    .fill(.primary)
                    .frame(width: 6, height: 6)
            }

            Button {
                appState.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Close Tab")
            }
            .buttonStyle(.plain)
            .help("Close Tab (⌘W)")
            .opacity(isActive ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.tabActiveBackground : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Cross-platform color helpers
extension Color {
    #if os(iOS)
    static let tabActiveBackground = Color(UIColor.systemBackground)
    static let secondarySystemBackgroundColor = Color(UIColor.secondarySystemBackground)
    #else
    static let tabActiveBackground = Color(NSColor.controlBackgroundColor)
    static let secondarySystemBackgroundColor = Color(NSColor.controlBackgroundColor)
    #endif
}

#if os(macOS)
extension NSColor {
    static let secondarySystemBackground = NSColor.controlBackgroundColor
}
#endif
