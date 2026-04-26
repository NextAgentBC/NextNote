import SwiftUI

struct FocusModeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            #if os(macOS)
            Color(NSColor.textBackgroundColor).ignoresSafeArea()
            #else
            Color(UIColor.systemBackground).ignoresSafeArea()
            #endif

            if let tabIndex = appState.activeTabIndex {
                EditorView(document: appState.openTabs[tabIndex].document)
                    #if os(macOS)
                    .padding(.horizontal, 80)
                    .padding(.vertical, 40)
                    #else
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    #endif
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        withAnimation { appState.isFocusMode = false }
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 18))
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding()
                    .opacity(0.6)
                }
            }
        }
    }
}
