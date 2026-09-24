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
            if !model.unreachableRules.isEmpty {
                Section {
                    ForEach(model.unreachableRules) { unreachable in
                        Label(unreachable.summary, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(IntakeColor.warning)
                    }
                } header: {
                    Text("Unreachable rules")
                } footer: {
                    Text("An earlier enabled rule already matches everything these would. Reorder them so the more specific rule comes first.")
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
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.extensions.isEmpty ? "Any type" : rule.extensionsDisplay)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if !rule.conditions.isEmpty {
                    Text(conditionsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.folderName), \(rule.extensionsDisplay), \(conditionsSummary)")
    }

    private var conditionsSummary: String {
        rule.conditions.map(\.summary).joined(separator: ", ")
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
    @State private var conditions: [RuleCondition]
    @State private var isEnabled: Bool
    @State private var subfolderPattern: SubfolderPattern
    @State private var errorMessage: String?

    init(item: RuleEditorItem) {
        self.item = item
        switch item {
        case .add:
            _folderName = State(initialValue: "")
            _extensionsText = State(initialValue: "")
            _conditions = State(initialValue: [])
            _isEnabled = State(initialValue: true)
            _subfolderPattern = State(initialValue: .none)
        case .edit(let rule):
            _folderName = State(initialValue: rule.folderName)
            _extensionsText = State(initialValue: rule.extensionsDisplay)
            _conditions = State(initialValue: rule.conditions)
            _isEnabled = State(initialValue: rule.isEnabled)
            _subfolderPattern = State(initialValue: rule.subfolderPattern)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder", text: $folderName)
                TextField(
                    "Extensions",
                    text: $extensionsText,
                    prompt: Text(conditions.isEmpty ? "psd, ai" : "psd, ai (or leave empty for any type)")
                )
                Toggle("Enabled", isOn: $isEnabled)
                Picker("Subfolders", selection: $subfolderPattern) {
                    ForEach(SubfolderPattern.allCases, id: \.self) { pattern in
                        Text(pattern.title).tag(pattern)
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(IntakeColor.danger)
                }
                conditionsSection
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
        .frame(minWidth: 480, minHeight: 320)
    }

    @ViewBuilder
    private var conditionsSection: some View {
        Section {
            ForEach(Array(conditions.enumerated()), id: \.offset) { index, _ in
                ConditionEditorRow(
                    condition: Binding(
                        get: { conditions[index] },
                        set: { conditions[index] = $0 }
                    ),
                    sourceDomainHint: sourceDomainHint
                )
            }
            .onDelete { offsets in
                conditions.remove(atOffsets: offsets)
            }
            Menu {
                ForEach(RuleCondition.Kind.allCases, id: \.self) { kind in
                    Button(kind.label) {
                        conditions.append(ConditionEditorRow.defaultCondition(for: kind))
                    }
                }
            } label: {
                Label("Add Condition", systemImage: "plus")
            }
        } header: {
            Text("Conditions")
        } footer: {
            Text(conditionsFooter)
        }
    }

    private var sourceDomainHint: String {
        model.recentSourceDomains.first ?? "bank.com"
    }

    private var conditionsFooter: String {
        var lines = ["All conditions must match (AND). With at least one condition, extensions can be left empty to match any type."]
        if !model.recentSourceDomains.isEmpty {
            lines.append("Recently seen: \(model.recentSourceDomains.joined(separator: ", ")).")
        }
        return lines.joined(separator: " ")
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
            let trimmedExtensions = extensionsText.trimmingCharacters(in: .whitespacesAndNewlines)
            let extensionsResult: Result<Set<String>, ExtensionToken.ParseError> = trimmedExtensions.isEmpty
                ? .success([])
                : ExtensionToken.parse(extensionsText)
            switch extensionsResult {
            case .failure(let error):
                errorMessage = error.description
            case .success(let tokens):
                guard !tokens.isEmpty || !conditions.isEmpty else {
                    errorMessage = "Add at least one extension or condition."
                    return
                }
                let id: String? = {
                    if case .edit(let rule) = item { return rule.id }
                    return nil
                }()
                model.saveRule(
                    id: id,
                    folderName: name,
                    extensions: tokens,
                    conditions: conditions,
                    isEnabled: isEnabled,
                    subfolderPattern: subfolderPattern
                )
                dismiss()
            }
        }
    }
}

private struct ConditionEditorRow: View {
    @Binding var condition: RuleCondition
    var sourceDomainHint: String

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: kindBinding) {
                ForEach(RuleCondition.Kind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 160)
            valueField
        }
    }

    @ViewBuilder
    private var valueField: some View {
        switch condition {
        case .sourceDomain(let value):
            TextField(sourceDomainHint, text: Binding(
                get: { value },
                set: { condition = .sourceDomain($0) }
            ))
        case .nameContains(let value):
            TextField("invoice", text: Binding(
                get: { value },
                set: { condition = .nameContains($0) }
            ))
        case .nameStartsWith(let value):
            TextField("IMG_", text: Binding(
                get: { value },
                set: { condition = .nameStartsWith($0) }
            ))
        case .nameMatchesWildcard(let value):
            TextField("IMG_*", text: Binding(
                get: { value },
                set: { condition = .nameMatchesWildcard($0) }
            ))
        case .sizeAtLeast(let bytes):
            SizeField(bytes: Binding(
                get: { bytes },
                set: { condition = .sizeAtLeast($0) }
            ))
        case .sizeAtMost(let bytes):
            SizeField(bytes: Binding(
                get: { bytes },
                set: { condition = .sizeAtMost($0) }
            ))
        }
    }

    private var kindBinding: Binding<RuleCondition.Kind> {
        Binding(
            get: { condition.kind },
            set: { condition = Self.defaultCondition(for: $0) }
        )
    }

    static func defaultCondition(for kind: RuleCondition.Kind) -> RuleCondition {
        switch kind {
        case .sourceDomain: .sourceDomain("")
        case .nameContains: .nameContains("")
        case .nameStartsWith: .nameStartsWith("")
        case .nameMatchesWildcard: .nameMatchesWildcard("")
        case .sizeAtLeast: .sizeAtLeast(0)
        case .sizeAtMost: .sizeAtMost(0)
        }
    }
}

/// A byte-size field edited in megabytes for readability; stores exact bytes.
private struct SizeField: View {
    @Binding var bytes: Int64
    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 4) {
            TextField("0", text: $text)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                .onAppear { text = Self.formatted(bytes) }
                .onChange(of: text) { _, newValue in
                    guard let megabytes = Double(newValue) else { return }
                    bytes = Int64((megabytes * 1_000_000).rounded())
                }
            Text("MB")
                .foregroundStyle(.secondary)
        }
    }

    private static func formatted(_ bytes: Int64) -> String {
        guard bytes != 0 else { return "" }
        return String(format: "%g", Double(bytes) / 1_000_000)
    }
}
