import SwiftUI
import IntakeCore

struct RulesSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default taxonomy")
                .font(.headline)
            Text("Rules match by file extension. Intake creates a folder only when a file is routed there.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
            .tableStyle(.inset)
            Text("Unmatched types go to Other, and only if something lands there.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
