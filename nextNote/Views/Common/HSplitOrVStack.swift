import SwiftUI

/// Adaptive split: HSplitView on macOS (draggable divider), HStack/VStack on
/// iOS depending on width. Used to side-by-side editor + preview.
struct HSplitOrVStack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
        HSplitView {
            content()
        }
        #else
        GeometryReader { geo in
            if geo.size.width > 600 {
                HStack(spacing: 0) {
                    content()
                }
            } else {
                VStack(spacing: 0) {
                    content()
                }
            }
        }
        #endif
    }
}
