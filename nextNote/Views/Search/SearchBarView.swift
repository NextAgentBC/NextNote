import SwiftUI

struct SearchBarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showReplace = false
    @State private var matchCount = 0
    @State private var currentMatch = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search row
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))

                TextField("Search...", text: $appState.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)
                    .onSubmit { findNext() }

                if !appState.searchText.isEmpty {
                    Text("\(currentMatch)/\(matchCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                // Search options
                Toggle(isOn: $appState.searchOptions.caseSensitive) {
                    Text("Aa")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Case Sensitive")

                Toggle(isOn: $appState.searchOptions.useRegex) {
                    Text(".*")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Regular Expression")

                Button { showReplace.toggle() } label: {
                    Image(systemName: showReplace ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)

                // Navigation
                Button { findPrevious() } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button { findNext() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("g", modifiers: .command)

                Button {
                    appState.toggleSearch()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Replace row
            if showReplace {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.swap")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))

                    TextField("Replace...", text: $appState.replaceText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))

                    Button("Replace") { replaceCurrent() }
                        .controlSize(.small)

                    Button("All") { replaceAll() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            Divider()
        }
        .background(Color(.secondarySystemBackground))
        .onAppear { isSearchFocused = true }
        .onChange(of: appState.searchText) { _, _ in
            updateMatchCount()
        }
    }

    private func updateMatchCount() {
        guard let document = appState.activeTab?.document,
              !appState.searchText.isEmpty else {
            matchCount = 0
            currentMatch = 0
            return
        }

        let options: String.CompareOptions = appState.searchOptions.caseSensitive ? [] : .caseInsensitive
        var count = 0
        var searchRange = document.content.startIndex..<document.content.endIndex

        while let range = document.content.range(of: appState.searchText, options: options, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<document.content.endIndex
        }

        matchCount = count
        currentMatch = count > 0 ? 1 : 0
    }

    private func findNext() {
        guard matchCount > 0 else { return }
        currentMatch = currentMatch < matchCount ? currentMatch + 1 : 1
    }

    private func findPrevious() {
        guard matchCount > 0 else { return }
        currentMatch = currentMatch > 1 ? currentMatch - 1 : matchCount
    }

    private func replaceCurrent() {
        guard let index = appState.activeTabIndex,
              !appState.searchText.isEmpty else { return }

        let doc = appState.openTabs[index].document
        let options: String.CompareOptions = appState.searchOptions.caseSensitive ? [] : .caseInsensitive

        if let range = doc.content.range(of: appState.searchText, options: options) {
            doc.content.replaceSubrange(range, with: appState.replaceText)
            doc.modifiedAt = Date()
            appState.openTabs[index].isModified = true
            updateMatchCount()
        }
    }

    private func replaceAll() {
        guard let index = appState.activeTabIndex,
              !appState.searchText.isEmpty else { return }

        let doc = appState.openTabs[index].document
        let options: String.CompareOptions = appState.searchOptions.caseSensitive ? [] : .caseInsensitive

        doc.content = doc.content.replacingOccurrences(
            of: appState.searchText,
            with: appState.replaceText,
            options: options
        )
        doc.modifiedAt = Date()
        appState.openTabs[index].isModified = true
        updateMatchCount()
    }
}
