import SwiftUI

struct AISettingsView: View {
    @StateObject private var prefs = UserPreferences.shared
    @ObservedObject private var aiService = AITextService.shared
    @AppStorage("aiModelId") private var selectedModelId = "mlx-community/Qwen3-4B-4bit"
    @AppStorage("hfToken") private var hfToken = ""
    @AppStorage("aiProviderType") private var aiProviderType = AIProviderType.onDevice.rawValue
    @State private var showTokenSetup = false
    @State private var connectionTestMessage: String = ""
    @State private var isTestingConnection = false

    private var isRemote: Bool { aiProviderType == AIProviderType.remote.rawValue }
    private var isGemini: Bool { aiProviderType == AIProviderType.gemini.rawValue }

    @State private var geminiKeyDraft: String = KeychainStore.get(.gemini) ?? ""
    @State private var geminiTestMessage: String = ""
    @State private var isTestingGemini = false

    @State private var remoteKeyDraft: String = KeychainStore.get(.openai) ?? ""

    var body: some View {
        Form {
            Section("General") {
                Toggle("Enable AI Features", isOn: $prefs.enableAI)

                Picker("AI Language", selection: $prefs.preferredAILanguage) {
                    ForEach(UserPreferences.supportedLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
            }

            Section("Provider") {
                Picker("AI Provider", selection: $aiProviderType) {
                    ForEach(AIProviderType.allCases, id: \.rawValue) { p in
                        Text(p.displayName).tag(p.rawValue)
                    }
                }
                .onChange(of: aiProviderType) { _, _ in
                    AITextService.shared.reconfigure()
                    connectionTestMessage = ""
                }
            }

            if isGemini {
                Section("Google Gemini") {
                    HStack {
                        Text("Model")
                        Spacer()
                        TextField("gemini-flash-latest", text: $prefs.geminiModelId)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key(s) — one per line, or comma-separated")
                            .font(.subheadline)
                        TextEditor(text: $geminiKeyDraft)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 80)
                            .border(Color.secondary.opacity(0.3))
                        HStack {
                            Button("Save Key") {
                                try? KeychainStore.set(geminiKeyDraft, for: .gemini)
                                AITextService.shared.reconfigure()
                                geminiTestMessage = "Saved to Keychain"
                            }
                            .disabled(geminiKeyDraft.isEmpty)

                            Button(role: .destructive) {
                                KeychainStore.delete(.gemini)
                                geminiKeyDraft = ""
                                AITextService.shared.reconfigure()
                                geminiTestMessage = "Cleared"
                            } label: { Text("Clear") }

                            Spacer()

                            Button {
                                Task {
                                    isTestingGemini = true
                                    geminiTestMessage = ""
                                    AITextService.shared.reconfigure()
                                    do {
                                        try await AITextService.shared.currentProvider.testConnection()
                                        geminiTestMessage = "Connected"
                                    } catch {
                                        geminiTestMessage = error.localizedDescription
                                    }
                                    isTestingGemini = false
                                }
                            } label: {
                                if isTestingGemini {
                                    Label("Testing…", systemImage: "arrow.trianglehead.2.clockwise")
                                } else {
                                    Label("Test", systemImage: "network")
                                }
                            }
                            .disabled(isTestingGemini)
                        }

                        if !geminiTestMessage.isEmpty {
                            Text(geminiTestMessage)
                                .font(.caption)
                                .foregroundStyle(geminiTestMessage == "Connected" || geminiTestMessage == "Saved to Keychain" ? .green : .red)
                        }

                        Text("Free tier: ~10–15 RPM, 250–1000 RPD. Dashboards and daily digests cache by content hash, so unchanged folders don't re-spend calls.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Usage Today") {
                    let quota = QuotaTracker.shared
                    LabeledContent("Requests today") {
                        Text("\(quota.requestsToday) / \(quota.dailyLimit)")
                    }
                    ProgressView(value: Double(quota.requestsToday), total: Double(max(1, quota.dailyLimit)))
                }
            } else if isRemote {
                Section("Remote Server") {
                    HStack {
                        Text("Base URL")
                        Spacer()
                        TextField("http://host:port/v1", text: $prefs.remoteBaseURL)
                            #if os(iOS)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Model")
                        Spacer()
                        TextField("model-name (blank = server default)", text: $prefs.remoteModelId)
                            #if os(iOS)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            #endif
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key (optional)")
                            .font(.subheadline)
                        SecureField("sk-…", text: $remoteKeyDraft)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Save Key") {
                                try? KeychainStore.set(remoteKeyDraft, for: .openai)
                                AITextService.shared.reconfigure()
                                connectionTestMessage = "Saved to Keychain"
                            }
                            .disabled(remoteKeyDraft.isEmpty)

                            Button(role: .destructive) {
                                KeychainStore.delete(.openai)
                                remoteKeyDraft = ""
                                AITextService.shared.reconfigure()
                                connectionTestMessage = "Cleared"
                            } label: { Text("Clear") }
                        }
                    }

                    Toggle("Disable model thinking (faster, Qwen only)", isOn: $prefs.remoteDisableThinking)
                        .onChange(of: prefs.remoteDisableThinking) { _, _ in
                            AITextService.shared.reconfigure()
                        }

                    HStack {
                        Button {
                            Task {
                                isTestingConnection = true
                                connectionTestMessage = ""
                                AITextService.shared.reconfigure()
                                do {
                                    try await AITextService.shared.currentProvider.testConnection()
                                    connectionTestMessage = "Connected"
                                } catch {
                                    connectionTestMessage = error.localizedDescription
                                }
                                isTestingConnection = false
                            }
                        } label: {
                            if isTestingConnection {
                                Label("Testing…", systemImage: "arrow.trianglehead.2.clockwise")
                            } else {
                                Label("Test Connection", systemImage: "network")
                            }
                        }
                        .disabled(isTestingConnection)

                        Spacer()

                        if !connectionTestMessage.isEmpty {
                            Text(connectionTestMessage)
                                .font(.caption)
                                .foregroundStyle(connectionTestMessage == "Connected" || connectionTestMessage == "Saved to Keychain" ? .green : .red)
                        }
                    }
                }
            } else {
                Section("On-Device Model") {
                    Picker("Model", selection: $selectedModelId) {
                        ForEach(AITextService.availableModels) { option in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name)
                                Text(option.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(option.id)
                        }
                    }

                    HStack {
                        Text("Status")
                        Spacer()
                        modelStatusBadge
                    }

                    modelActionRow

                    if case .downloading(let progress) = aiService.modelState {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: progress)
                            Text("\(Int(progress * 100))% — Downloading...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if case .error(let msg) = aiService.modelState {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("HuggingFace Token") {
                    HStack {
                        if hfToken.isEmpty {
                            Label("Not configured", systemImage: "key")
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Token saved (hf_•••\(hfToken.suffix(4)))", systemImage: "key.fill")
                                .foregroundStyle(.green)
                        }
                        Spacer()
                    }

                    Button {
                        showTokenSetup = true
                    } label: {
                        Label(
                            hfToken.isEmpty ? "Setup Gemma 4 Access (4 steps)" : "Reconfigure Token",
                            systemImage: hfToken.isEmpty ? "arrow.right.circle" : "arrow.triangle.2.circlepath"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(hfToken.isEmpty ? .purple : .secondary)

                    if hfToken.isEmpty && selectedModelRequiresToken {
                        Text("Gemma 4 requires a free HuggingFace account and token.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .sheet(isPresented: $showTokenSetup) {
                    #if os(macOS)
                    HFTokenSetupView()
                        .frame(width: 500, height: 600)
                    #else
                    NavigationStack {
                        HFTokenSetupView()
                            .navigationTitle("Gemma 4 Setup")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Done") { showTokenSetup = false }
                                }
                            }
                    }
                    #endif
                }
            }

            Section("Features") {
                Toggle("Auto Grammar Check", isOn: $prefs.autoGrammarCheck)

                if aiService.tokensPerSecond > 0 {
                    HStack {
                        Text("Last Speed")
                        Spacer()
                        Text("\(aiService.tokensPerSecond, specifier: "%.1f") tokens/sec")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI")
    }

    private var selectedModelRequiresToken: Bool {
        AITextService.availableModels.first { $0.id == selectedModelId }?.requiresToken ?? false
    }

    @ViewBuilder
    private var modelStatusBadge: some View {
        switch aiService.modelState {
        case .notDownloaded:
            Text("Not Downloaded")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.gray.opacity(0.15), in: Capsule())
                .foregroundStyle(.secondary)
        case .downloading:
            Text("Downloading...")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.15), in: Capsule())
                .foregroundStyle(.blue)
        case .loading:
            Text("Loading...")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.15), in: Capsule())
                .foregroundStyle(.orange)
        case .ready:
            Text("Ready")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.15), in: Capsule())
                .foregroundStyle(.green)
        case .error:
            Text("Error")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.15), in: Capsule())
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var modelActionRow: some View {
        switch aiService.modelState {
        case .notDownloaded, .error:
            Button {
                Task { await aiService.downloadModel() }
            } label: {
                Label("Download Model (~1.5 GB)", systemImage: "arrow.down.circle")
            }
        case .downloading:
            Button(role: .destructive) {
                // Cancel not implemented yet
            } label: {
                Label("Downloading...", systemImage: "stop.circle")
            }
            .disabled(true)
        case .ready:
            Button(role: .destructive) {
                aiService.deleteModel()
            } label: {
                Label("Delete Model (Free Space)", systemImage: "trash")
            }
        case .loading:
            ProgressView()
        }
    }
}
