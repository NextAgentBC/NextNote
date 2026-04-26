import SwiftUI

struct AISettingsView: View {
    @StateObject private var settings = AIProviderSettings.shared
    @StateObject private var aiService = AIService()

    @State private var apiKeyInput: String = ""
    @State private var testResult: AIService.TestResult?
    @State private var isTesting = false
    @State private var showChatTooltip = false
    @State private var showEmbedTooltip = false

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $settings.activeProvider) {
                    ForEach(AIProvider.presets) { preset in
                        Text(preset.name).tag(preset)
                    }
                }
            }

            Section("Endpoints") {
                if isCustom {
                    TextField("Chat URL", text: chatURLBinding)
                    TextField("Chat Model", text: Binding(
                        get: { settings.activeProvider.chatModel },
                        set: { settings.activeProvider.chatModel = $0 }
                    ))
                    TextField("Embed URL", text: embedURLBinding)
                    TextField("Embed Model", text: Binding(
                        get: { settings.activeProvider.embedModel },
                        set: { settings.activeProvider.embedModel = $0 }
                    ))
                } else {
                    labelRow("Chat URL", value: settings.activeProvider.chatBaseURL.absoluteString)
                    labelRow("Chat Model", value: settings.activeProvider.chatModel)
                    labelRow("Embed URL", value: settings.activeProvider.embedBaseURL.absoluteString)
                    labelRow("Embed Model", value: settings.activeProvider.embedModel.isEmpty ? "—" : settings.activeProvider.embedModel)
                }
            }

            if settings.activeProvider.requiresAPIKey {
                Section("API Key") {
                    SecureField("API Key", text: $apiKeyInput)
                        .onAppear {
                            apiKeyInput = settings.apiKey(for: settings.activeProvider) ?? ""
                        }
                        .onChange(of: settings.activeProvider) { _, newProvider in
                            apiKeyInput = settings.apiKey(for: newProvider) ?? ""
                        }
                    Button("Save Key") {
                        settings.setAPIKey(apiKeyInput, for: settings.activeProvider)
                    }
                    .disabled(apiKeyInput.isEmpty)
                }
            }

            Section("Connection") {
                Button(isTesting ? "Testing…" : "Test Connection") {
                    runTest()
                }
                .disabled(isTesting)

                if let result = testResult {
                    HStack(spacing: 8) {
                        statusDot(ok: result.chat, label: "Chat", error: result.chatError)
                        statusDot(ok: result.embed, label: "Embed", error: result.embedError)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI")
    }

    private var isCustom: Bool {
        settings.activeProvider.id == AIProvider.custom.id
    }

    private var chatURLBinding: Binding<String> {
        Binding(
            get: { settings.activeProvider.chatBaseURL.absoluteString },
            set: { str in
                if let url = URL(string: str) {
                    settings.activeProvider.chatBaseURL = url
                }
            }
        )
    }

    private var embedURLBinding: Binding<String> {
        Binding(
            get: { settings.activeProvider.embedBaseURL.absoluteString },
            set: { str in
                if let url = URL(string: str) {
                    settings.activeProvider.embedBaseURL = url
                }
            }
        )
    }

    @ViewBuilder
    private func labelRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private func statusDot(ok: Bool, label: String, error: String?) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ok ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(ok ? Color.primary : Color.red)
            if let error, !ok {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(error)
            }
        }
    }

    private func runTest() {
        isTesting = true
        testResult = nil
        Task {
            let result = await aiService.testConnection()
            await MainActor.run {
                testResult = result
                isTesting = false
            }
        }
    }
}
