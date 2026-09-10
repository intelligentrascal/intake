import SwiftUI
import IntakeCore

enum AIProviderPlaceholder: String, CaseIterable, Identifiable {
    case ollama
    case claude
    case cursor
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ollama: "Ollama (local)"
        case .claude: "Claude CLI"
        case .cursor: "Cursor agent CLI"
        case .codex: "Codex CLI"
        }
    }

    var detail: String {
        switch self {
        case .ollama: "Local models, when installed"
        case .claude: "Uses the claude command if present"
        case .cursor: "Uses the agent command if present"
        case .codex: "Uses the codex command if present"
        }
    }
}

struct AISettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var apiKeyDraft = ""
    @State private var keyIsSaved = false

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
                ForEach(AIProviderPlaceholder.allCases) { provider in
                    LabeledContent(provider.title) {
                        Text("Unavailable")
                            .foregroundStyle(.secondary)
                    }
                    Text(provider.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Other providers")
            } footer: {
                Text("Ollama and CLI providers stay placeholders for now.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            keyIsSaved = OpenRouterKeychain.hasKey
        }
    }

    private func saveKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        OpenRouterKeychain.save(trimmed)
        apiKeyDraft = ""
        keyIsSaved = OpenRouterKeychain.hasKey
        model.openRouterStatusMessage = nil
    }
}
