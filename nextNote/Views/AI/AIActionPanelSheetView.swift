#if os(iOS)
import SwiftUI

struct AIActionPanelSheetView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var aiService = AITextService.shared
    @Binding var isPresented: Bool

    @State private var selectedAction: AIAction = .polish
    @State private var result: String = ""
    @State private var isProcessing: Bool = false
    @State private var targetLanguage: String = "English"
    @State private var polishStyle: PolishStyle = .concise
    @State private var summaryLength: SummaryLength = .medium

    enum AIAction: String, CaseIterable, Identifiable {
        case polish = "Polish"
        case summarize = "Summarize"
        case continueWriting = "Continue"
        case translate = "Translate"
        case grammar = "Grammar"
        case simplify = "Simplify"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .polish: return "wand.and.stars"
            case .summarize: return "text.redaction"
            case .continueWriting: return "text.append"
            case .translate: return "globe"
            case .grammar: return "checkmark.circle"
            case .simplify: return "arrow.triangle.branch"
            }
        }
    }

    private var currentText: String {
        appState.activeTab?.document.content ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            if aiService.modelState != .ready {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("AI model not downloaded. Go to Settings → AI to download.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AIAction.allCases) { action in
                        Button {
                            selectedAction = action
                        } label: {
                            Label(action.rawValue, systemImage: action.icon)
                                .font(.system(size: 13))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selectedAction == action
                                    ? Color.accentColor.opacity(0.15)
                                    : Color(.secondarySystemBackground),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            Divider()

            iOSActionOptions
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            if isProcessing {
                HStack {
                    ProgressView()
                    Text("Processing...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if !result.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Result")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Copy") {
                            UIPasteboard.general.string = result
                        }
                        .font(.caption)
                        Button("Replace") {
                            replaceContent()
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                    }
                    ScrollView {
                        Text(result)
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }

            Spacer()

            HStack {
                Text("\(currentText.count) chars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await executeAction() }
                } label: {
                    Label("Run AI", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentText.isEmpty || isProcessing || aiService.modelState != .ready)
            }
            .padding()
        }
        .navigationTitle("AI Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { isPresented = false }
            }
        }
    }

    @ViewBuilder
    private var iOSActionOptions: some View {
        switch selectedAction {
        case .polish:
            Picker("Style", selection: $polishStyle) {
                ForEach(PolishStyle.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
        case .summarize:
            Picker("Length", selection: $summaryLength) {
                Text("Brief").tag(SummaryLength.brief)
                Text("Medium").tag(SummaryLength.medium)
                Text("Detailed").tag(SummaryLength.detailed)
            }
            .pickerStyle(.segmented)
        case .translate:
            Picker("To", selection: $targetLanguage) {
                Text("English").tag("English")
                Text("中文").tag("Simplified Chinese")
                Text("日本語").tag("Japanese")
                Text("한국어").tag("Korean")
                Text("Français").tag("French")
            }
            .pickerStyle(.segmented)
        default:
            EmptyView()
        }
    }

    private func executeAction() async {
        isProcessing = true
        result = ""
        let text = currentText

        switch selectedAction {
        case .polish:
            result = await aiService.polish(text, style: polishStyle)
        case .summarize:
            result = await aiService.summarize(text, length: summaryLength)
        case .continueWriting:
            var acc = ""
            for await chunk in await aiService.continueWriting(text) {
                acc += chunk
                result = acc
            }
        case .translate:
            result = await aiService.translate(text, to: targetLanguage)
        case .grammar:
            let suggestions = await aiService.checkGrammar(text)
            result = suggestions.isEmpty
                ? "No issues found."
                : suggestions.map { "• \($0.original) → \($0.suggestion)" }.joined(separator: "\n")
        case .simplify:
            result = await aiService.polish(text, style: .concise)
        }
        isProcessing = false
    }

    private func replaceContent() {
        guard let index = appState.activeTabIndex else { return }
        appState.openTabs[index].document.content = result
        appState.openTabs[index].isModified = true
        isPresented = false
    }
}
#endif
