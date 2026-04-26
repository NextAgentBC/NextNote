import SwiftUI

/// Inline table-of-contents panel that lives inside the reader. Replaces
/// the per-book TOC dropdown the sidebar used to render — that approach
/// did string-format matching between TOC href and spine href, which
/// silently broke for ~half the EPUBs in the wild.
///
/// This drawer reads the spine index resolved at parse time
/// (`BookTOCEntry.spineIndex`), so a TOC click is a plain integer jump.
/// Calibre / foliate / Apple Books all converge on this design — the
/// EPUB's logical addressing (spine index + anchor) is the only thing
/// guaranteed to round-trip; everything else is publisher gloss.
struct EPUBTOCDrawer: View {
    let toc: [BookTOCEntry]
    let spine: [BookSpineEntry]
    let currentSpineIndex: Int
    let onJump: (_ spineIndex: Int, _ anchor: String?) -> Void
    let onClose: () -> Void

    @State private var query: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if !query.isEmpty || !flat.isEmpty {
                searchField
            }
            Divider().opacity(query.isEmpty && flat.isEmpty ? 0 : 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let rows = filteredRows
                    if rows.isEmpty {
                        emptyHint
                    } else {
                        ForEach(rows) { row in
                            tocRow(row)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        #if os(macOS)
        .background(Color(nsColor: .underPageBackgroundColor))
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Contents")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Filter", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty
                 ? "This EPUB has no table of contents."
                 : "No matches.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if query.isEmpty {
                Text("Use ⌘[ / ⌘] to walk through chapters.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    // MARK: - Rows

    @ViewBuilder
    private func tocRow(_ row: FlatRow) -> some View {
        let isCurrent = row.spineIndex == currentSpineIndex && row.anchor == nil
        let resolvable = row.spineIndex != nil

        Button {
            guard let idx = row.spineIndex else { return }
            onJump(idx, row.anchor)
        } label: {
            HStack(alignment: .top, spacing: 4) {
                Text(row.title.isEmpty ? "Untitled" : row.title)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(
                        isCurrent ? AnyShapeStyle(Color.accentColor) :
                        (resolvable ? AnyShapeStyle(HierarchicalShapeStyle.primary)
                                    : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                    )
                Spacer(minLength: 0)
            }
            .padding(.leading, 12 + CGFloat(row.depth) * 12)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!resolvable)
    }

    // MARK: - Flatten + filter

    private struct FlatRow: Identifiable {
        let id: String
        let title: String
        let spineIndex: Int?
        let anchor: String?
        let depth: Int
    }

    private var flat: [FlatRow] {
        var out: [FlatRow] = []
        func walk(_ entries: [BookTOCEntry], depth: Int) {
            for e in entries {
                out.append(FlatRow(
                    id: "\(out.count)-\(e.title)-\(e.href)",
                    title: e.title,
                    spineIndex: e.spineIndex,
                    anchor: e.anchor,
                    depth: depth
                ))
                walk(e.children, depth: depth + 1)
            }
        }
        walk(toc, depth: 0)
        return out
    }

    private var filteredRows: [FlatRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return flat }
        return flat.filter { $0.title.lowercased().contains(q) }
    }
}
