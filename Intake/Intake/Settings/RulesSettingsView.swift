import SwiftUI
import IntakeCore

struct RulesSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var editor: RuleEditorItem?
    @State private var selectedRuleID: RoutingRule.ID?

    var body: some View {
        Form {
            suggestionsSection
            if !model.ruleConflicts.isEmpty {
                Section {
                    ForEach(model.ruleConflicts) { conflict in
                        Label(conflict.summary, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(IntakeColor.warning)
                    }
                } header: {
                    Text("Conflicts")
                } footer: {
                    Text("When two enabled rules list the same extension, the first in this list wins.")
                }
            }
            Section {
                List(selection: $selectedRuleID) {
                    ForEach(model.rules) { rule in
                        RuleRowView(rule: rule)
                            .tag(rule.id)
                            .contextMenu {
                                Button("Edit…") {
                                    editor = .edit(rule)
                                }
                                if rule.isBuiltIn {
                                    Button("Reset to Default") {
                                        model.resetBuiltInRule(id: rule.id)
                                    }
                                } else {
                                    Button("Delete", role: .destructive) {
                                        model.deleteCustomRule(id: rule.id)
                                        if selectedRuleID == rule.id {
                                            selectedRuleID = nil
                                        }
                                    }
                                }
                            }
                    }
                    .onMove { source, destination in
                        model.moveRules(from: source, to: destination)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 280)
                HStack {
                    Button("Add Rule…") {
                        editor = .add
                    }
                    Button("Edit…") {
                        if let rule = selectedRule {
                            editor = .edit(rule)
                        }
                    }
                    .disabled(selectedRule == nil)
                    if let rule = selectedRule, rule.isBuiltIn {
                        Button("Reset to Default") {
                            model.resetBuiltInRule(id: rule.id)
                        }
                    }
                    if let rule = selectedRule, !rule.isBuiltIn {
                        Button("Delete", role: .destructive) {
                            model.deleteCustomRule(id: rule.id)
                            selectedRuleID = nil
                        }
                    }
                    Spacer()
                }
            } header: {
                Text("Default taxonomy")
            } footer: {
                Text("Rules match by file extension. Folders appear only when a file is routed there. Drag to change order — first match wins. Unmatched types go to Other, and only if something lands there.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshSuggestions()
        }
        .sheet(item: $editor) { item in
            RuleEditorSheet(item: item)
                .environment(model)
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        Section {
            if model.ruleSuggestions.isEmpty {
                ContentUnavailableView(
                    "No suggestions yet",
                    systemImage: "lightbulb",
                    description: Text("Suggestions appear after Intake sees repeating file types.")
                )
                .frame(minHeight: 120)
            } else {
                ForEach(model.ruleSuggestions) { suggestion in
                    SuggestionRowView(suggestion: suggestion)
                }
            }
        } header: {
            Text("Suggestions")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggestions never change files until you accept. They stay on this Mac — Intake does not read file contents or go online to propose rules.")
                if !model.suggestionMemory.neverExtensions.isEmpty
                    || !model.suggestionMemory.dismissedUntil.isEmpty {
                    Button("Reset dismissed suggestions") {
                        model.resetDismissedSuggestions()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var selectedRule: RoutingRule? {
        guard let selectedRuleID else { return nil }
        return model.rules.first { $0.id == selectedRuleID }
    }
}

private struct RuleRowView: View {
    @Environment(AppModel.self) private var model
    var rule: RoutingRule

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Toggle("Enabled", isOn: model.binding(for: rule))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 28)
            Label(rule.folderName, systemImage: rule.systemImage)
                .frame(minWidth: 140, alignment: .leading)
            Text(rule.extensionsDisplay)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.folderName), \(rule.extensionsDisplay)")
    }
}

private struct SuggestionRowView: View {
    @Environment(AppModel.self) private var model
    var suggestion: RuleSuggestion

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: suggestion.systemImage)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                Text(suggestion.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Accept") {
                model.acceptSuggestion(suggestion)
            }
            .buttonStyle(.borderedProminent)
            Button("Dismiss") {
                model.dismissSuggestion(suggestion)
            }
            Button("Never") {
                model.neverSuggestion(suggestion)
            }
            .buttonStyle(.borderless)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(suggestion.title). \(suggestion.subtitle)")
    }
}

enum RuleEditorItem: Identifiable {
    case add
    case edit(RoutingRule)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let rule): rule.id
        }
    }
}

struct RuleEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var item: RuleEditorItem

    @State private var folderName: String
    @State private var extensionsText: String
    @State private var isEnabled: Bool
    @State private var errorMessage: String?

    init(item: RuleEditorItem) {
        self.item = item
        switch item {
        case .add:
            _folderName = State(initialValue: "")
            _extensionsText = State(initialValue: "")
            _isEnabled = State(initialValue: true)
        case .edit(let rule):
            _folderName = State(initialValue: rule.folderName)
            _extensionsText = State(initialValue: rule.extensionsDisplay)
            _isEnabled = State(initialValue: rule.isEnabled)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder", text: $folderName)
                TextField("Extensions", text: $extensionsText, prompt: Text("psd, ai"))
                Toggle("Enabled", isOn: $isEnabled)
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(IntakeColor.danger)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 240)
    }

    private var title: String {
        switch item {
        case .add: "Add Rule"
        case .edit: "Edit Rule"
        }
    }

    private func save() {
        switch FolderNameToken.parse(folderName) {
        case .failure(let error):
            errorMessage = error.description
            return
        case .success(let name):
            switch ExtensionToken.parse(extensionsText) {
            case .failure(let error):
                errorMessage = error.description
            case .success(let tokens):
                let id: String? = {
                    if case .edit(let rule) = item { return rule.id }
                    return nil
                }()
                model.saveRule(
                    id: id,
                    folderName: name,
                    extensions: tokens,
                    isEnabled: isEnabled
                )
                dismiss()
            }
        }
    }
}
