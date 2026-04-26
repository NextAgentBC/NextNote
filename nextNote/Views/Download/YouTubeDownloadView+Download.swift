import SwiftUI
import SwiftData

extension YouTubeDownloadView {
    var canDownload: Bool {
        locator.binaryURL != nil
            && locator.downloadFolderURL != nil
            && !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Submit a download as a background job and dismiss the sheet. The
    /// `DownloadJobCoordinator` owns the queue, persists progress to
    /// SwiftData, and surfaces the running job in `DownloadHistoryView`.
    func startDownload() {
        let url = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        let modeEnum: DownloadJob.Mode = (mode == .audio) ? .audio : .video

        DownloadJobCoordinator.shared.submit(
            sourceURL: url,
            mode: modeEnum,
            qualityRaw: qualityRaw,
            saveTo: saveToRaw,
            autoClassify: autoClassify,
            modelContext: modelContext,
            libraryRoots: libraryRoots,
            appState: appState,
            library: library,
            player: player
        )

        // Reset local form state and close — user watches progress in
        // the History view, frees the sheet for the next URL.
        urlText = ""
        searchResults = []
        searchError = nil
        statusLine = "Submitted to download queue."
        lastOutputURL = nil
        lastError = nil
        appState.showYouTubeDownload = false
        appState.showDownloadHistory = true
    }
}
