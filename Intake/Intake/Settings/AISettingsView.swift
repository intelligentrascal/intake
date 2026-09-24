import SwiftUI
import IntakeCore

struct AISettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var apiKeyDraft = ""
    @State private var keyIsSaved = false
    @State private var otherProviders: [OtherAIProviderPresence] = OtherAIProviderDetector.scan()
    @State private var keyInfo: OpenRouterKeyInfo?
    @State private var creditsInfo: OpenRouterCreditsInfo?
    @State private var lastLookupTime: Date?
    @State private var isLoading = false
    @State private var showResetConfirmation = false

    private let lookupDebounceInterval: TimeInterval = 60

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Suggest names and folders with AI", isOn: $model.aiSuggestionsEnabled)
            } footer: {
                Text("Off by default. Core organizing uses extension rules only. Intake never sends file contents unless you turn this on and enable a provider.")
            }
            Section {
                Toggle("Enable OpenRouter", isOn: $model.openRouterEnabled)
                    .disabled(!model.aiSuggestionsEnabled)
                SecureField(
                    keyIsSaved ? "Key saved in Keychain" : "API key",
                    text: $apiKeyDraft
                )
                .textContentType(.password)
                .onSubmit(saveKey)
                HStack {
                    Button(keyIsSaved ? "Replace Key" : "Save Key") {
                        saveKey()
                    }
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if keyIsSaved {
                        Button("Remove Key", role: .destructive) {
                            OpenRouterKeychain.delete()
                            apiKeyDraft = ""
                            keyIsSaved = false
                            keyInfo = nil
                            creditsInfo = nil
                        }
                    }
                }
                TextField("Base URL", text: $model.openRouterBaseURL)
                Picker("Model", selection: $model.openRouterModel) {
                    ForEach(OpenRouterConfiguration.curatedModels, id: \.self) { name in
                        Text(name).tag(name)
                    }
                    if !OpenRouterConfiguration.curatedModels.contains(model.openRouterModel) {
                        Text(model.openRouterModel).tag(model.openRouterModel)
                    }
                }
                TextField("Custom model", text: $model.openRouterModel)
                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Fetching account info...")
                            .foregroundStyle(.secondary)
                    }
                } else if let keyInfo {
                    LabeledContent("API Key", value: keyInfo.label)
                    LabeledContent("Key Usage", value: String(format: "$%.4f", keyInfo.usage))
                    LabeledContent("Remaining Limit", value: String(format: "$%.2f", keyInfo.limitRemaining))
                }
                if let creditsInfo {
                    LabeledContent("Account Credits", value: String(format: "$%.2f", creditsInfo.totalCredits))
                }
                if model.openRouterSpendTracker.totalSpend > 0 {
                    Divider()
                    LabeledContent("Total Intake Spend", value: String(format: "$%.4f", model.openRouterSpendTracker.totalSpend))
                    LabeledContent("This Month", value: String(format: "$%.4f", model.openRouterSpendTracker.monthlySpend))
                    Button("Reset Spend", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .alert("Reset Intake Spending?", isPresented: $showResetConfirmation) {
                        Button("Cancel", role: .cancel) { }
                        Button("Reset", role: .destructive) {
                            var tracker = model.openRouterSpendTracker
                            tracker.resetAll()
                            model.openRouterSpendTracker = tracker
                        }
                    } message: {
                        Text("This will reset both total and monthly spending to zero.")
                    }
                }
                if let status = model.openRouterStatusMessage {
                    Text(status)
                        .foregroundStyle(IntakeColor.warning)
                } else if model.canCallOpenRouter {
                    Text("Ready. Suggestions run only on rule misses.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("OpenRouter")
            } footer: {
                Text("The API key is stored in Keychain, not in preferences. Local rules run first. Network calls happen only when AI suggestions and OpenRouter are both on. File contents are not uploaded.")
            }
            Section {
                ForEach(otherProviders) { presence in
                    LabeledContent(presence.provider.title) {
                        Text(presence.statusTitle)
                            .foregroundStyle(presence.isAvailable ? IntakeColor.success : .secondary)
                    }
                    Text(presence.provider.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let found = presence.foundOnPathDetail, presence.provider == .cursor {
                        Text(found)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Other providers")
            } footer: {
                Text("Detection only — checks PATH plus ~/.local/bin and Homebrew (outside the App Sandbox container home). Does not call these CLIs. Install a CLI to enable it in a later release. OpenRouter remains the working provider.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            keyIsSaved = OpenRouterKeychain.hasKey
            otherProviders = OtherAIProviderDetector.scan()
            lookupAccountInfo()
        }
    }

    private func saveKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        OpenRouterKeychain.save(trimmed)
        apiKeyDraft = ""
        keyIsSaved = OpenRouterKeychain.hasKey
        model.openRouterStatusMessage = nil
        keyInfo = nil
        creditsInfo = nil
        lastLookupTime = nil
        lookupAccountInfo()
    }

    private func lookupAccountInfo() {
        guard model.aiSuggestionsEnabled, model.openRouterEnabled else { return }
        guard let key = OpenRouterKeychain.load() else { return }

        // Debounce lookups to at most once per minute
        if let lastTime = lastLookupTime, Date().timeIntervalSince(lastTime) < lookupDebounceInterval {
            return
        }

        isLoading = true
        Task {
            let keyResult = await OpenRouterClient.fetchKeyInfo(
                apiKey: key,
                baseURL: model.openRouterBaseURL
            )
            let creditsResult = await OpenRouterClient.fetchCreditsInfo(
                apiKey: key,
                baseURL: model.openRouterBaseURL
            )

            await MainActor.run {
                isLoading = false
                lastLookupTime = Date()

                if case .success(let info) = keyResult {
                    keyInfo = info
                } else if case .failure(let error) = keyResult {
                    model.openRouterStatusMessage = error.userMessage
                }

                if case .success(let info) = creditsResult {
                    creditsInfo = info
                } else if case .failure(let error) = creditsResult {
                    if model.openRouterStatusMessage == nil {
                        model.openRouterStatusMessage = error.userMessage
                    }
                }
            }
        }
    }
}
