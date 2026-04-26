import SwiftUI

extension YouTubeDownloadView {
    var searchResultsList: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Search Results")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    searchResults = []
                    searchError = nil
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(searchResults) { r in
                        Button {
                            // Load chosen result into the URL field and kick
                            // off the normal download path — same quality /
                            // mode / classify settings apply.
                            urlText = r.watchURL.absoluteString
                            searchResults = []
                            startDownload()
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: mode == .audio ? "music.note" : "play.rectangle")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(2)
                                        .truncationMode(.tail)
                                        .multilineTextAlignment(.leading)
                                    HStack(spacing: 6) {
                                        if let u = r.uploader {
                                            Text(u)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let d = r.duration {
                                            Text("·").foregroundStyle(.tertiary)
                                            Text(d).foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.system(size: 10))
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.04))
                        )
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    func runSearch() {
        guard let binary = locator.binaryURL else { return }
        let q = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        searchError = nil
        searchResults = []
        Task {
            do {
                let results = try await YTDLPSearch.search(query: q, count: 8, binary: binary)
                searchResults = results
                if results.isEmpty {
                    searchError = "No results."
                }
            } catch {
                searchError = error.localizedDescription
            }
            isSearching = false
        }
    }

    func isChannelOrPlaylistURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        guard lower.contains("youtube.com") || lower.contains("youtu.be") else { return false }
        return lower.contains("/@")
            || lower.contains("/channel/")
            || lower.contains("/c/")
            || lower.contains("/user/")
            || lower.contains("/playlist")
    }
}
