#if os(macOS)
import SwiftUI
import PDFKit

/// NSViewRepresentable wrapper around AnnotatingPDFView. External code drives
/// navigation via `requestedPage`; internal page changes report back via
/// `onPageChange`; edits flip `onEdited`.
struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var requestedPage: Int
    var tool: PDFAnnTool
    var inkColor: NSColor
    var lineWidth: CGFloat
    let onPageChange: (Int) -> Void
    let onEdited: () -> Void

    func makeNSView(context: Context) -> AnnotatingPDFView {
        let view = AnnotatingPDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor.windowBackgroundColor
        view.tool = tool
        view.inkColor = inkColor
        view.lineWidth = lineWidth
        view.onEdited = onEdited
        if let page = document.page(at: requestedPage) {
            view.go(to: page)
        }
        context.coordinator.attach(view: view)
        return view
    }

    func updateNSView(_ view: AnnotatingPDFView, context: Context) {
        view.tool = tool
        view.inkColor = inkColor
        view.lineWidth = lineWidth
        view.onEdited = onEdited
        guard let target = document.page(at: requestedPage) else { return }
        if view.currentPage != target {
            view.go(to: target)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: PDFKitView
        weak var view: PDFView?

        init(parent: PDFKitView) {
            self.parent = parent
            super.init()
        }

        func attach(view: PDFView) {
            self.view = view
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(pageChanged(_:)),
                name: .PDFViewPageChanged,
                object: view
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func pageChanged(_ note: Notification) {
            guard let view = view, let page = view.currentPage else { return }
            let idx = view.document?.index(for: page) ?? 0
            parent.onPageChange(idx)
        }
    }
}
#endif
