import SwiftUI

extension AssetLibraryView {
    /// Two-row header — titles + actions on top, filter + search on a
    /// second row. Stops the whole thing from wrapping awkwardly when
    /// the sheet is at its minimum width.
    var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text("Asset Library")
                    .font(.title2.bold())
                    .lineLimit(1)
                    .fixedSize()
                Text("\(filteredAssets.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button {
                    openImportPanel()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import files from disk")

                Button {
                    pasteFromClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut("v", modifiers: [.command])
                .help("Paste image from clipboard (⌘V)")

                Button {
                    revealRootInFinder()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Reveal the Assets folder in Finder")

                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 10) {
                Picker("", selection: $kindFilter) {
                    ForEach(KindFilter.allCases) { k in
                        Text(k.rawValue).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .labelsHidden()

                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(12)
    }
}
