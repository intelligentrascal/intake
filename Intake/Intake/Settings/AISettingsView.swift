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
                Text("Off by default. Core ingest uses extension rules only. Providers are not wired yet.")
                    .foregroundStyle(.secondary)
            }
            Section("Providers") {
                ForEach(AIProviderPlaceholder.allCases) { provider in
                    LabeledContent(provider.title) {
                        Text("Unavailable")
                            .foregroundStyle(.secondary)
                    }
                    Text(provider.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Intake never sends file contents to a network service unless you turn a provider on in a later release.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
