import SwiftUI

struct SettingsView: View {
    @StateObject private var preferences = UserPreferences.shared
    @EnvironmentObject private var appState: AppState

    var body: some View {
        #if os(macOS)
        TabView {
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            EditorSettingsView()
                .tabItem { Label("Editor", systemImage: "doc.text") }
            AISettingsView()
                .tabItem { Label("AI", systemImage: "brain") }
            VaultSettingsView()
                .tabItem { Label("Vault", systemImage: "folder") }
            SyncSettingsView()
                .tabItem { Label("Sync", systemImage: "icloud") }
        }
        .frame(width: 520, height: 550)
        #else
        NavigationStack {
            List {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    Label("Appearance", systemImage: "paintbrush")
                }
                NavigationLink {
                    EditorSettingsView()
                } label: {
                    Label("Editor", systemImage: "doc.text")
                }
                NavigationLink {
                    AISettingsView()
                } label: {
                    Label("AI", systemImage: "brain")
                }
                NavigationLink {
                    SyncSettingsView()
                } label: {
                    Label("Sync", systemImage: "icloud")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
        #endif
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @StateObject private var prefs = UserPreferences.shared

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Mode", selection: $prefs.themeMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }

            Section("Font") {
                Picker("Font", selection: $prefs.fontName) {
                    Text("SF Mono").tag("SF Mono")
                    Text("Menlo").tag("Menlo")
                    Text("Courier").tag("Courier")
                    Text("SF Pro").tag("SF Pro")
                    Text("New York").tag("New York")
                }

                HStack {
                    Text("Size: \(Int(prefs.fontSize))pt")
                    Slider(value: $prefs.fontSize, in: 12...36, step: 1)
                }

                HStack {
                    Text("Line Spacing: \(prefs.lineSpacing, specifier: "%.1f")")
                    Slider(value: $prefs.lineSpacing, in: 1.0...2.5, step: 0.1)
                }
            }

            Section("Display") {
                Toggle("Show Line Numbers", isOn: $prefs.showLineNumbers)
                Toggle("Wrap Lines", isOn: $prefs.wrapLines)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}

// MARK: - Editor Settings

struct EditorSettingsView: View {
    @StateObject private var prefs = UserPreferences.shared

    var body: some View {
        Form {
            Section("New Document") {
                Picker("Default Format", selection: $prefs.defaultFileType) {
                    ForEach(FileType.allCases) { type in
                        Text(type.displayName).tag(type.rawValue)
                    }
                }
            }

            Section("Editing") {
                Toggle("Auto Indent", isOn: $prefs.autoIndent)

                Picker("Tab Width", selection: $prefs.tabWidth) {
                    Text("2 spaces").tag(2)
                    Text("4 spaces").tag(4)
                    Text("8 spaces").tag(8)
                }
            }

            Section("Auto Save") {
                Picker("Interval", selection: $prefs.autoSaveInterval) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("Manual only").tag(0)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Editor")
    }
}

// MARK: - AI Settings

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

// MARK: - Vault Settings (R1 feature-flagged redesign)

struct VaultSettingsView: View {
    @StateObject private var prefs = UserPreferences.shared
    @EnvironmentObject private var vault: VaultStore

    var body: some View {
        Form {
            Section {
                Toggle("Enable vault mode (directory-backed)", isOn: $prefs.vaultMode)
                Text("Switches the sidebar from the flat SwiftData list to a real folder tree rooted at a folder on disk. Files stay as plain .md so Finder, git, and other editors work normally. Full disk-backed saves land in R2.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Vault Mode")
            }

            if prefs.vaultMode {
                Section {
                    if let root = vault.root {
                        LabeledContent("Current vault") {
                            Text(root.path)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        HStack {
                            Button {
                                Task { await vault.pickVault() }
                            } label: { Text("Change Vault…") }
                            Button(role: .destructive) {
                                vault.forgetVault()
                            } label: { Text("Forget Vault") }
                            Spacer()
                            Button {
                                Task { await vault.scan() }
                            } label: { Text("Rescan") }
                                .disabled(vault.isScanning)
                        }
                    } else {
                        Button {
                            Task { await vault.pickVault() }
                        } label: { Text("Choose Vault…") }
                    }

                    if let err = vault.lastError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Vault Folder")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Vault")
    }
}

// MARK: - Sync Settings

struct SyncSettingsView: View {
    @StateObject private var prefs = UserPreferences.shared

    var body: some View {
        Form {
            Section("iCloud") {
                Toggle("Enable iCloud Sync", isOn: $prefs.enableICloudSync)
                Text("Documents will sync across your Apple devices via iCloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Sync")
    }
}
