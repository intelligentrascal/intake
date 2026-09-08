import SwiftUI

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

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Suggest names and folders with AI", isOn: $model.aiSuggestionsEnabled)
            } footer: {
                Text("Off by default. Core organizing uses extension rules only.")
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
                Text("Providers")
            } footer: {
                Text("Intake does not send file contents to a network service unless you enable a provider.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
