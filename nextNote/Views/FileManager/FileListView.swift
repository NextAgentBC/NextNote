import SwiftUI
import SwiftData

struct FileListView: View {
    let documents: [TextDocument]
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @AppStorage("defaultFileType") private var defaultFileTypeRaw: String = FileType.txt.rawValue
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .modified
    @State private var renamingDoc: TextDocument?
    @State private var renameText = ""

    enum SortOrder: String, CaseIterable {
        case modified = "Modified"
        case name = "Name"
        case type = "Type"
    }

    private var filteredDocuments: [TextDocument] {
        let filtered: [TextDocument]
        if searchText.isEmpty {
            filtered = documents
        } else {
            filtered = documents.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }

        switch sortOrder {
        case .modified:
            return filtered.sorted { $0.modifiedAt > $1.modifiedAt }
        case .name:
            return filtered.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .type:
            return filtered.sorted { $0.fileTypeRaw < $1.fileTypeRaw }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sort picker
            Picker("Sort", selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // File list
            List {
                ForEach(filteredDocuments) { doc in
                    FileRowView(document: doc)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.openNewTab(document: doc)
                            #if os(iOS)
                            appState.showFileManager = false
                            #endif
                        }
                        .contextMenu {
                            Button {
                                appState.openNewTab(document: doc)
                            } label: {
                                Label("Open", systemImage: "doc.text")
                            }
                            Button {
                                renameText = doc.title
                                renamingDoc = doc
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button {
                                doc.isFavorite.toggle()
                            } label: {
                                Label(
                                    doc.isFavorite ? "Unfavorite" : "Favorite",
                                    systemImage: doc.isFavorite ? "star.slash" : "star"
                                )
                            }
                            Divider()
                            Button(role: .destructive) {
                                deleteDocument(doc)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteDocument(doc)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete(perform: deleteDocuments)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search files...")
            .alert("Rename", isPresented: Binding(
                get: { renamingDoc != nil },
                set: { if !$0 { renamingDoc = nil } }
            )) {
                TextField("Document name", text: $renameText)
                Button("Cancel", role: .cancel) { renamingDoc = nil }
                Button("Rename") {
                    if let doc = renamingDoc, !renameText.isEmpty {
                        doc.title = renameText
                        doc.modifiedAt = Date()
                    }
                    renamingDoc = nil
                }
            } message: {
                Text("Enter a new name for this document.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    createNewDocument()
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
            }
        }
    }

    private func createNewDocument() {
        let defaultType = FileType(rawValue: defaultFileTypeRaw) ?? .txt
        let doc = TextDocument(fileType: defaultType)
        modelContext.insert(doc)
        appState.openNewTab(document: doc)
        #if os(iOS)
        appState.showFileManager = false
        #endif
    }

    private func deleteDocument(_ doc: TextDocument) {
        if let tabIndex = appState.openTabs.firstIndex(where: { $0.document.id == doc.id }) {
            appState.closeTab(id: appState.openTabs[tabIndex].id)
        }
        modelContext.delete(doc)
    }

    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets {
            deleteDocument(filteredDocuments[index])
        }
    }
}

struct FileRowView: View {
    let document: TextDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: document.fileType.iconName)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(document.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)

                    if document.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                    }
                }

                HStack(spacing: 8) {
                    Text(document.modifiedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text("\(document.wordCount) words")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                if !document.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(document.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1), in: Capsule())
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
