import SwiftUI

/// Guided HuggingFace token setup flow — walks user through registration,
/// Gemma 4 license acceptance, and token creation.
struct HFTokenSetupView: View {
    @AppStorage("hfToken") private var hfToken = ""
    @State private var tokenInput = ""
    @State private var currentStep = 1
    @State private var isValidating = false
    @State private var validationResult: ValidationResult?

    enum ValidationResult {
        case success
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerView

                Divider()

                // Step 1: Register
                stepView(
                    number: 1,
                    title: "Create HuggingFace Account",
                    description: "Free account required to access Gemma 4 model.",
                    buttonLabel: "Open HuggingFace Sign Up",
                    url: "https://huggingface.co/join"
                )

                // Step 2: Accept Gemma 4 License
                stepView(
                    number: 2,
                    title: "Accept Gemma 4 License",
                    description: "Google requires you to accept the Gemma usage terms. Click the button below, scroll down and click \"Agree and access repository\".",
                    buttonLabel: "Open Gemma 4 Model Page",
                    url: "https://huggingface.co/google/gemma-4-E2B-it"
                )

                // Step 3: Create Token
                step3CreateToken

                // Step 4: Paste Token
                step4PasteToken

                Divider()

                // Status
                statusView
            }
            .padding(20)
        }
        .frame(minWidth: 400, minHeight: 500)
        .onAppear {
            tokenInput = hfToken
            if !hfToken.isEmpty { currentStep = 4 }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain")
                .font(.system(size: 32))
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("Gemma 4 Setup")
                    .font(.title2.bold())
                Text("4 quick steps to enable the most powerful on-device AI")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step View

    private func stepView(number: Int, title: String, description: String, buttonLabel: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                stepBadge(number: number)
                Text(title)
                    .font(.headline)
                if number < currentStep {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, 36)

            Button {
                openURL(url)
                if currentStep <= number {
                    withAnimation { currentStep = number + 1 }
                }
            } label: {
                HStack {
                    Image(systemName: "safari")
                    Text(buttonLabel)
                }
            }
            .buttonStyle(.bordered)
            .padding(.leading, 36)
            .disabled(number > currentStep)
            .opacity(number > currentStep ? 0.5 : 1)
        }
    }

    // MARK: - Step 3: Create Token (with permission guide)

    private var step3CreateToken: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                stepBadge(number: 3)
                Text("Create Access Token")
                    .font(.headline)
                if currentStep > 3 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Create a **Fine-grained** token with these permissions:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                // Permission checklist
                VStack(alignment: .leading, spacing: 4) {
                    permissionItem("Read access to contents of all public gated repos you can access", highlight: true)
                }
                .padding(10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                Text("Other permissions can be left unchecked.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 36)

            Button {
                openURL("https://huggingface.co/settings/tokens/new?tokenType=fineGrained")
                if currentStep <= 3 {
                    withAnimation { currentStep = 4 }
                }
            } label: {
                HStack {
                    Image(systemName: "safari")
                    Text("Open Token Settings")
                }
            }
            .buttonStyle(.bordered)
            .padding(.leading, 36)
            .disabled(3 > currentStep)
            .opacity(3 > currentStep ? 0.5 : 1)
        }
    }

    private func permissionItem(_ text: String, highlight: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.square.fill")
                .foregroundStyle(highlight ? .orange : .secondary)
                .font(.system(size: 14))
            Text(text)
                .font(.caption)
                .foregroundStyle(highlight ? .primary : .secondary)
        }
    }

    // MARK: - Step 4: Paste Token

    private var step4PasteToken: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                stepBadge(number: 4)
                Text("Paste Your Token")
                    .font(.headline)
                if !hfToken.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Text("Paste the token you just created (starts with hf_...)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, 36)

            HStack {
                SecureField("hf_...", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)

                Button {
                    #if os(macOS)
                    if let clipboard = NSPasteboard.general.string(forType: .string) {
                        tokenInput = clipboard
                    }
                    #else
                    if let clipboard = UIPasteboard.general.string {
                        tokenInput = clipboard
                    }
                    #endif
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .help("Paste from clipboard")

                Button {
                    Task { await validateAndSave() }
                } label: {
                    if isValidating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Verify")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(tokenInput.isEmpty || isValidating)
            }
            .padding(.leading, 36)
            .disabled(currentStep < 4)
            .opacity(currentStep < 4 ? 0.5 : 1)

            // Validation result
            if let result = validationResult {
                HStack {
                    switch result {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Token verified! You can now download Gemma 4.")
                            .foregroundStyle(.green)
                    case .failed(let msg):
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(msg)
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .padding(.leading, 36)
            }
        }
    }

    // MARK: - Status

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hfToken.isEmpty {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text("All Set!")
                            .font(.headline)
                        Text("Close this window and click \"Download Model\" in AI settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Helpers

    private func stepBadge(number: Int) -> some View {
        ZStack {
            Circle()
                .fill(number <= currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                .frame(width: 26, height: 26)
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(number <= currentStep ? .white : .secondary)
        }
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    private func validateAndSave() async {
        isValidating = true
        validationResult = nil

        // Test the token by hitting HuggingFace API
        guard let url = URL(string: "https://huggingface.co/api/whoami-v2") else {
            validationResult = .failed("Invalid URL")
            isValidating = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(tokenInput)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                hfToken = tokenInput
                validationResult = .success
            } else {
                validationResult = .failed("Invalid token. Please check and try again.")
            }
        } catch {
            validationResult = .failed("Network error: \(error.localizedDescription)")
        }

        isValidating = false
    }
}
