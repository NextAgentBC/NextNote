import SwiftUI

// ⌘⇧N quick-capture. Paste a URL or free text, pick a destination (swipe,
// inbox, ingest), hit Save — the HUD composes the right slash command and
// injects it into the embedded terminal so Claude Code actually does the work.
// The HUD never writes files directly; the skill is the source of truth.
struct CaptureHUD: View {
    @EnvironmentObject private var appState: AppState

    enum Destination: String, CaseIterable, Identifiable {
        case swipe
        case inbox
        case ingest
        var id: String { rawValue }
        var label: String {
            switch self {
            case .swipe:  return "Swipe"
            case .inbox:  return "Inbox"
            case .ingest: return "Ingest → Wiki"
            }
        }
        var skill: String {
            switch self {
            case .swipe:  return "swipe-save"
            case .inbox:  return "kickoff"   // placeholder — inbox capture goes via kickoff's intake
            case .ingest: return "ingest"
            }
        }
        var hint: String {
            switch self {
            case .swipe:  return "Save structure to 70_Swipe/ and 80_Raw/."
            case .inbox:  return "Drop into 00_Inbox/ for later triage."
            case .ingest: return "Pull source into 80_Raw/ and compile atomic wiki pages."
            }
        }
    }

    @State private var text: String = ""
    @State private var destination: Destination = .swipe

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            editor
            destinationPicker
            Text(destination.hint)
                .font(.caption)
                .foregroundStyle(.secondary)
            footer
        }
        .padding(16)
        .frame(width: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .onAppear {
            // Auto-populate from clipboard when it looks useful (URL or ≥ 40
            // chars of prose). Leave empty for short clipboard contents —
            // those are usually accidental selections.
            if let pasted = NSPasteboard.general.string(forType: .string),
               looksCaptureWorthy(pasted) {
                text = pasted
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(systemName: "tray.and.arrow.down")
                .foregroundStyle(.secondary)
            Text("Quick Capture")
                .font(.headline)
            Spacer()
            Button {
                appState.showCaptureHUD = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var editor: some View {
        TextEditor(text: $text)
            .font(.system(size: 13))
            .frame(minHeight: 110, maxHeight: 220)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.separator, lineWidth: 0.5)
            )
    }

    private var destinationPicker: some View {
        Picker("", selection: $destination) {
            ForEach(Destination.allCases) { dest in
                Text(dest.label).tag(dest)
            }
        }
        .pickerStyle(.segmented)
    }

    private var footer: some View {
        HStack {
            Text(charCountLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Cancel") {
                appState.showCaptureHUD = false
            }
            .keyboardShortcut(.cancelAction)
            Button("Save") {
                dispatch()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var charCountLabel: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmed.count) chars"
    }

    // MARK: - Dispatch

    private func dispatch() {
        let payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return }

        // The skill expects an argument — a URL, a file path, or pasted text.
        // Shell-quote so multi-line paste survives going through the terminal.
        let quoted = shellQuote(payload)
        let command = "claude \"/\(destination.skill) \(quoted)\""

        appState.showTerminal = true
        appState.pendingTerminalCommand = command
        appState.showCaptureHUD = false
    }

    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func looksCaptureWorthy(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.lowercased().hasPrefix("http://") { return true }
        if trimmed.lowercased().hasPrefix("https://") { return true }
        return trimmed.count >= 40
    }
}
