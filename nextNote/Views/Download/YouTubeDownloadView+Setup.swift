import SwiftUI

extension YouTubeDownloadView {
    var disclaimerBox: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("YouTube's Terms of Service restrict downloading. Use only for content you own or have explicit rights to — you are responsible for compliance.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    func setupRow(
        label: String,
        pathText: String,
        action: String,
        onAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(pathText)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
            Spacer()
            Button(action, action: onAction)
                .controlSize(.small)
                .disabled(isRunning)
        }
    }

    /// "Installed and ready" row — green check + path + discreet Change…
    /// button. Used when the binary was auto-detected and adopted.
    func toolStatusRow(
        label: String,
        path: String,
        installed: Bool,
        onChange: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
            Text(path)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Change…", action: onChange)
                .controlSize(.small)
                .disabled(isRunning)
        }
    }

    /// Installation hint — red/amber icon + exact brew command to paste
    /// into Terminal. Keeps the Choose… escape hatch for users on a
    /// non-standard install path.
    func installHintRow(
        label: String,
        command: String,
        why: String,
        onChoose: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .foregroundStyle(.orange)
                    Text(command)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button {
                        PasteboardActions.copy(command)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy to clipboard")
                }
                Text(why)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Choose…", action: onChoose)
                .controlSize(.small)
                .disabled(isRunning)
        }
    }
}
