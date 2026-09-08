import SwiftUI
import IntakeCore

struct RulesSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Table(model.rules) {
                    TableColumn("On") { rule in
                        Toggle("Enabled", isOn: model.binding(for: rule))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                    }
                    .width(36)
                    TableColumn("Folder") { rule in
                        Label(rule.category.folderName, systemImage: rule.category.systemImage)
                    }
                    .width(min: 140, ideal: 180)
                    TableColumn("Extensions") { rule in
                        Text(rule.extensionsDisplay)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(minHeight: 280)
            } header: {
                Text("Default taxonomy")
            } footer: {
                Text("Rules match by file extension. Folders appear only when a file is routed there. Unmatched types go to Other, and only if something lands there.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
